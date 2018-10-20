# sink support
prep!(T, A) = A, 0
prep!(::Type{Union{T, Missing}}, A) where {T} = T[ifelse(ismissing(x), zero(T), x) for x in A]
prep!(::Type{Union{Dates.Date, Missing}}, A) = ODBC.API.SQLDate[ismissing(x) ? ODBC.API.SQLDate() : ODBC.API.SQLDate(x) for x in A], 0
prep!(::Type{Union{Dates.DateTime, Missing}}, A) = ODBC.API.SQLTimestamp[ismissing(x) ? ODBC.API.SQLTimestamp() : ODBC.API.SQLTimestamp(x) for x in A], 0
prep!(::Type{Union{Dec64, Missing}}, A) = Float64[ismissing(x) ? 0.0 : Float64(x) for x in A], 0

getptrlen(x::AbstractString) = pointer(Vector{UInt8}(x)), length(x), UInt8[]
getptrlen(x::WeakRefString{T}) where {T} = convert(Ptr{UInt8}, x.ptr), codeunits2bytes(T, x.len), UInt8[]
getptrlen(x::Missing) = convert(Ptr{UInt8}, C_NULL), 0, UInt8[]
function getptrlen(x::CategoricalArrays.CategoricalValue)
    ref = Vector{UInt8}(String(x))
    return pointer(ref), length(ref), ref
end

prep!(::Type{T}, A) where {T <: AbstractString} = _prep!(T, A)
prep!(::Type{Union{T, Missing}}, A) where {T <: AbstractString} = _prep!(T, A)
prep!(::Type{T}, A) where {T <: CategoricalValue} = _prep!(T, A)
prep!(::Type{Union{T, Missing}}, A) where {T <: CategoricalValue} = _prep!(T, A)

function _prep!(T, column)
    maxlen = maximum(ODBC.clength, column)
    data = zeros(UInt8, maxlen * length(column))
    ind = 1
    for i = 1:length(column)
        ptr, len, ref = getptrlen(column[i])
        unsafe_copyto!(pointer(data, ind), ptr, len)
        ind += maxlen
    end
    return data, maxlen
end

function prep!(column::T, col, columns, indcols) where {T}
    columns[col], maxlen = prep!(eltype(T), column)
    indcols[col] = ODBC.API.SQLLEN[clength(x) for x in column]
    return length(column), maxlen
end

getCtype(::Type{T}) where {T} = get(ODBC.API.julia2C, T, ODBC.API.SQL_C_CHAR)
getCtype(::Type{Union{T, Missing}}) where {T} = get(ODBC.API.julia2C, T, ODBC.API.SQL_C_CHAR)
getCtype(::Type{Vector{T}}) where {T} = get(ODBC.API.julia2C, T, ODBC.API.SQL_C_CHAR)
getCtype(::Type{Vector{Union{T, Missing}}}) where {T} = get(ODBC.API.julia2C, T, ODBC.API.SQL_C_CHAR)

function load!(dsn::DSN, table::AbstractString, itr::T) where {T}
    Tables.istable(T) || throw(ArgumentError("$T doesn't support the required Tables.jl interface"))
    stmt = dsn.stmt_ptr2
    ODBC.execute!(dsn, "select * from $table", stmt)
    df = DataFrame(itr)
    M, N = size(df)
    columns = Vector{Any}(undef, N)
    indcols = Vector{Any}(undef, N)
    for (col, column) in enumerate(Tables.eachcolumn(df))
        rows, len = prep!(column, col, columns, indcols)
        @CHECK stmt API.SQL_HANDLE_STMT API.SQLBindCols(stmt, col, getCtype(eltype(column)), columns[col], M, indcols[col])
    end
    API.SQLSetStmtAttr(stmt, API.SQL_ATTR_ROW_ARRAY_SIZE, M, API.SQL_IS_UINTEGER)
    @CHECK stmt API.SQL_HANDLE_STMT API.SQLBulkOperations(stmt, API.SQL_ADD)
    return
end

# function load(dsn::DSN, table::AbstractString, ::Type{T}, args...; append::Bool=false, transforms::Dict=Dict{Int,Function}()) where {T}
#     sink = Data.stream!(T(args...), ODBC.Sink, dsn, table; append=append, transforms=transforms)
#     return Data.close!(sink)
# end
# function load(dsn::DSN, table::AbstractString, source; append::Bool=false, transforms::Dict=Dict{Int,Function}())
#     sink = Data.stream!(source, ODBC.Sink, dsn, table; append=append, transforms=transforms)
#     return Data.close!(sink)
# end

# load(sink::Sink, ::Type{T}, args...; append::Bool=false, transforms::Dict=Dict{Int,Function}()) where {T} = (sink = Data.stream!(T(args...), sink; append=append, transforms=transforms); return Data.close!(sink))
# load(sink::Sink, source; append::Bool=false, transforms::Dict=Dict{Int,Function}()) = (sink = Data.stream!(source, sink; append=append, transforms=transforms); return Data.close!(sink))

# function Data.stream!(source, ::Type{Data.Column}, sink::ODBC.Sink, append::Bool=false)
#     Data.types(source) == Data.types(sink) || throw(ArgumentError("schema mismatch: \n$(Data.schema(source))\nvs.\n$(Data.schema(sink))"))
#     rows, cols = size(source)
#     Data.isdone(source, 1, 1) && return sink
#     ODBC.execute!(sink.dsn, "select * from $(sink.table)")
#     stmt = sink.dsn.stmt_ptr
#     types = Data.types(source)
#     columns = Vector{Any}(cols)
#     indcols = Array{Vector{ODBC.API.SQLLEN}}(cols)
#     row = 0
#     # get the column names for a table from the DB to generate the insert into sql statement
#     # might have to try quoting
#     # SQLPrepare (hdlStmt, (SQLTCHAR*)"INSERT INTO customers (CustID, CustName,  Phone_Number) VALUES(?,?,?)", SQL_NTS) ;
#     try
#         # SQLSetConnectAttr(hdlDbc, SQL_ATTR_AUTOCOMMIT, SQL_AUTOCOMMIT_OFF, SQL_NTS)
#         while !Data.isdone(source, row+1, cols+1)
#
#             for col = 1:cols
#                 T = types[col]
#                 # SQLBindParameter(hdlStmt, 1, SQL_PARAM_INPUT, SQL_C_LONG, SQL_INTEGER, 0, 0, (SQLPOINTER)custIDs, sizeof(SQLINTEGER) , NULL);
#                 rows, cT = ODBC.bindcolumn!(source, T, col, columns, indcols)
#                 ret = ODBC.API.SQLBindCols(stmt, col, cT, pointer(columns[col]), sizeof(eltype(columns[col])), indcols[col])
#                 println("$col: $ret")
#             end
#             ODBC.API.SQLSetStmtAttr(stmt, ODBC.API.SQL_ATTR_ROW_ARRAY_SIZE, rows, ODBC.API.SQL_IS_UINTEGER)
#             # SQLSetStmtAttr( hdlStmt, SQL_ATTR_PARAMSET_SIZE, (SQLPOINTER)NUM_ENTRIES, 0 );
#             # ret = SQLExecute(hdlStmt);
#             ODBC.@CHECK stmt ODBC.API.SQL_HANDLE_STMT ODBC.API.SQLBulkOperations(stmt, ODBC.API.SQL_ADD)
#             row += rows
#         end
#         # SQLEndTran(SQL_HANDLE_DBC, hdlDbc, SQL_COMMIT);
#     # finally
#         # SQLSetConnectAttr(hdlDbc, SQL_ATTR_AUTOCOMMIT, SQL_AUTOCOMMIT_ON, SQL_NTS);
#     end
#     Data.setrows!(source, row)
#     return sink
# end
