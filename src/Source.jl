# "Allocate ODBC handles for interacting with the ODBC Driver Manager"
function ODBCAllocHandle(handletype, parenthandle)
    handle = Ref{Ptr{Void}}()
    ODBC.API.SQLAllocHandle(handletype, parenthandle, handle)
    handle = handle[]
    if handletype == ODBC.API.SQL_HANDLE_ENV
        ODBC.API.SQLSetEnvAttr(handle, ODBC.API.SQL_ATTR_ODBC_VERSION, ODBC.API.SQL_OV_ODBC3)
    end
    return handle
end

# "Alternative connect function that allows user to create datasources on the fly through opening the ODBC admin"
function ODBCDriverConnect!(dbc::Ptr{Void}, conn_string, prompt::Bool)
    @static if is_windows()
        driver_prompt = prompt ? ODBC.API.SQL_DRIVER_PROMPT : ODBC.API.SQL_DRIVER_NOPROMPT
        window_handle = prompt ? ccall((:GetForegroundWindow, :user32), Ptr{Void}, () ) : C_NULL
    else
        driver_prompt = ODBC.API.SQL_DRIVER_NOPROMPT
        window_handle = C_NULL
    end
    out_conn = Block(ODBC.API.SQLWCHAR, BUFLEN)
    out_buff = Ref{Int16}()
    @CHECK(
        dbc,
        ODBC.API.SQL_HANDLE_DBC,
        ODBC.API.SQLDriverConnect(
            dbc,
            window_handle,
            conn_string,
            out_conn.ptr,
            BUFLEN,
            out_buff,
            driver_prompt
        )
    )
    connection_string = string(out_conn, out_buff[])
    return connection_string
end

"`ODBC.prepare` prepares an SQL statement to be executed"
function prepare(dsn::DSN, query::AbstractString)
    stmt = ODBCAllocHandle(ODBC.API.SQL_HANDLE_STMT, dsn.dbc_ptr)
    ODBC.@CHECK stmt ODBC.API.SQL_HANDLE_STMT ODBC.API.SQLPrepare(stmt, query)
    return Statement(dsn, stmt, query, Task(1))
end

isnull{T}(x::Nullable{T}) = Base.isnull(x)
isnull(x) = false

cast(x::Any) = x
cast(x::Date) = ODBC.API.SQLDate(x)
cast(x::DateTime) = ODBC.API.SQLTimestamp(x)
cast(x::String) = WeakRefString(pointer(Vector{UInt8}(x)), length(x))

getpointer{T}(::Type{T}, A, i) = unsafe_load(Ptr{Ptr{Void}}(pointer(A, i)))
getpointer{T}(::Type{WeakRefString{T}}, A, i) = convert(Ptr{Void}, A[i].ptr)
getpointer(::Type{String}, A, i) = convert(Ptr{Void}, pointer(Vector{UInt8}(A[i])))

sqllength(x) = 1
sqllength(x::AbstractString) = length(x)
sqllength(x::Vector{UInt8}) = length(x)
sqllength(x::ODBC.API.SQLDate) = 10
sqllength(x::Union{ODBC.API.SQLTime,ODBC.API.SQLTimestamp}) = length(string(x))

clength(x) = 1
clength(x::AbstractString) = length(x)
clength(x::Vector{UInt8}) = length(x)
clength{T}(x::WeakRefString{T}) = codeunits2bytes(T, length(x))
clength(x::CategoricalArrays.CategoricalValue) = length(String(x))
clength{T}(x::Nullable{T}) = isnull(x) ? ODBC.API.SQL_NULL_DATA : clength(get(x))

digits(x) = 0
digits(x::ODBC.API.SQLTimestamp) = length(string(x.fraction * 1000000))

function bind_vals!(stmt::Ptr{Void}, values::Union{Array, Tuple})
    values2 = Any[cast(x) for x in values]
    pointers = Ptr[]
    types = map(typeof, values2)
    for (i, v) in enumerate(values2)
        if isnull(v)
            ODBC.@CHECK(
                stmt,
                ODBC.API.SQL_HANDLE_STMT,
                ODBC.API.SQLBindParameter(
                    stmt,
                    i,
                    ODBC.API.SQL_PARAM_INPUT,
                    ODBC.API.SQL_C_CHAR,
                    ODBC.API.SQL_CHAR,
                    0,
                    0,
                    C_NULL,
                    0,
                    Ref(ODBC.API.SQL_NULL_DATA)
                )
            )
        else
            ctype, sqltype = ODBC.API.julia2C[types[i]], ODBC.API.julia2SQL[types[i]]
            csize, len, dgts = sqllength(v), clength(v), digits(v)
            ptr = getpointer(types[i], values2, i)
            # println("ctype: $ctype, sqltype: $sqltype, digits: $dgts, len: $len, csize: $csize")
            push!(pointers, ptr)
            ODBC.@CHECK(
                stmt,
                ODBC.API.SQL_HANDLE_STMT,
                ODBC.API.SQLBindParameter(
                    stmt,
                    i,
                    ODBC.API.SQL_PARAM_INPUT,
                    ctype,
                    sqltype,
                    csize,
                    dgts,
                    ptr,
                    len,
                    Ref(len)
                )
            )
        end
    end
end

function execute!(statement::Statement, values::Union{Array, Tuple})
    bind_vals!(statement.stmt, values)
    execute!(statement)
end

function execute!(statement::Statement)
    @CHECK statement.stmt ODBC.API.SQL_HANDLE_STMT ODBC.API.SQLExecute(statement.stmt)
end

"`ODBC.execute!` is a minimal method for just executing an SQL `query` string. No results are checked for or returned."
function execute!(dsn::DSN, sql::AbstractString, stmt::Ptr{Void}=dsn.stmt_ptr)
    ODBC.ODBCFreeStmt!(stmt)
    @CHECK stmt ODBC.API.SQL_HANDLE_STMT ODBC.API.SQLExecDirect(stmt, sql)
    return
end

inner_eltype{T}(::Type{NullableVector{T}}) = T

function build_source(stmt::Ptr{Void}, dsn::DSN, sql::AbstractString; weakrefstrings::Bool=true)
    rows, cols = Ref{Int}(), Ref{Int16}()
    ODBC.API.SQLNumResultCols(stmt, cols)
    ODBC.API.SQLRowCount(stmt, rows)
    rows, cols = rows[], cols[]
    #Allocate arrays to hold each column's metadata
    cnames = Array{String}(cols)
    sqltypes, csizes = Array{ODBC.API.SQLSMALLINT}(cols), Array{ODBC.API.SQLULEN}(cols)
    cdigits, cnulls = Array{ODBC.API.SQLSMALLINT}(cols), Array{ODBC.API.SQLSMALLINT}(cols)
    juliatypes = Array{DataType}(cols)
    alloctypes = Array{DataType}(cols)
    longtexts = Array{Bool}(cols)
    longtext = false
    #Allocate space for and fetch the name, type, size, etc. for each column
    len, dt, csize = Ref{ODBC.API.SQLSMALLINT}(), Ref{ODBC.API.SQLSMALLINT}(), Ref{ODBC.API.SQLULEN}()
    digits, null = Ref{ODBC.API.SQLSMALLINT}(), Ref{ODBC.API.SQLSMALLINT}()
    cname = ODBC.Block(ODBC.API.SQLWCHAR, ODBC.BUFLEN)
    for x = 1:cols
        ODBC.API.SQLDescribeCol(stmt, x, cname.ptr, ODBC.BUFLEN, len, dt, csize, digits, null)
        cnames[x] = string(cname, len[])
        t = dt[]
        sqltypes[x], csizes[x], cdigits[x], cnulls[x] = t, csize[], digits[], null[]
        alloctypes[x], juliatypes[x], longtexts[x] = ODBC.API.SQL2Julia[t]
        longtext |= longtexts[x]
    end
    if !weakrefstrings
        juliatypes = DataType[
            inner_eltype(T) <: WeakRefString ? NullableVector{String} : T for T in juliatypes
        ]
    end
    # Determine fetch strategy
    # rows might be -1 (dbms doesn't return total rows in resultset), 0 (empty resultset), or 1+
    if longtext
        rowset = allocsize = 1
    elseif rows > -1
        # rowset = min(rows, ODBC.API.MAXFETCHSIZE)
        allocsize = rowset = rows
    else
        rowset = allocsize = 1
    end
    ODBC.API.SQLSetStmtAttr(stmt, ODBC.API.SQL_ATTR_ROW_ARRAY_SIZE, rowset, ODBC.API.SQL_IS_UINTEGER)
    columns = Array{Any}(cols)
    boundcols = Array{Any}(cols)
    indcols = Array{Vector{ODBC.API.SQLLEN}}(cols)
    for x = 1:cols
        if longtexts[x]
            boundcols[x], indcols[x] = alloctypes[x][], ODBC.API.SQLLEN[]
        else
            boundcols[x], elsize = allocate(alloctypes[x], rowset, csizes[x])
            indcols[x] = Array{ODBC.API.SQLLEN}(rowset)
            ODBC.API.SQLBindCols(
                stmt,
                x,
                ODBC.API.SQL2C[sqltypes[x]],
                pointer(boundcols[x]),
                elsize,
                indcols[x]
            )
        end
    end
    schema = Data.Schema(
        cnames,
        juliatypes,
        rows,
        Dict(
            "types"=>[ODBC.API.SQL_TYPES[c] for c in sqltypes],
            "sizes"=>csizes,
            "digits"=>cdigits,
            "nulls"=>cnulls
        )
    )
    rowsfetched = Ref{ODBC.API.SQLLEN}() # will be populated by call to SQLFetchScroll
    ODBC.API.SQLSetStmtAttr(stmt, ODBC.API.SQL_ATTR_ROWS_FETCHED_PTR, rowsfetched, ODBC.API.SQL_NTS)
    ctypes = [ODBC.API.SQL2C[sqltypes[x]] for x = 1:cols]
    jl_longtypes = similar(juliatypes)
    for (i, T) in enumerate(juliatypes)
        innertype = inner_eltype(T)
        jl_longtypes[i] = longtexts[i] ? ODBC.API.Long{innertype} : innertype
    end
    source = ODBC.Source(
        schema,
        dsn,
        stmt,
        sql,
        columns,
        100,
        rowsfetched,
        0,
        boundcols,
        indcols,
        csizes,
        ctypes,
        jl_longtypes
    )
    rows != 0 && fetch!(source)
    return source
end

"""
`ODBC.Source` constructs a valid `Data.Source` type that executes an SQL `query` string for the `dsn` ODBC DSN.
Results are checked for and an `ODBC.ResultBlock` is allocated to prepare for fetching the resultset.
"""
function Source(dsn::DSN, sql::AbstractString; weakrefstrings::Bool=true, noquery::Bool=false)
    stmt = dsn.stmt_ptr
    noquery || ODBC.ODBCFreeStmt!(stmt)
    noquery || (ODBC.@CHECK stmt ODBC.API.SQL_HANDLE_STMT ODBC.API.SQLExecDirect(stmt, sql))
    return build_source(stmt, dsn, sql; weakrefstrings=weakrefstrings)
end

function Source(statement::Statement, freestmt::Bool=true; weakrefstrings::Bool=true, noquery::Bool=false)
    if ! noquery
        freestmt && ODBC.ODBCFreeStmt!(statement.stmt)
        ODBC.@CHECK statement.stmt ODBC.API.SQL_HANDLE_STMT ODBC.API.SQLExecute(statement.stmt)
    end
    return build_source(statement.stmt, statement.dsn, statement.query; weakrefstrings=weakrefstrings)
end

function Source(statement::Statement, values::Union{Array, Tuple}; weakrefstrings::Bool=true, noquery::Bool=false)
    noquery || ODBC.ODBCFreeStmt!(statement.stmt)
    noquery || bind_vals!(statement.stmt, values)
    return Source(statement, false; weakrefstrings=weakrefstrings, noquery=noquery)
end

# primitive types
allocate{T}(::Type{T}, rowset, size) = Vector{T}(rowset), sizeof(T)
# string/binary types
allocate{T<:Union{UInt8,UInt16,UInt32}}(::Type{T}, rowset, size) = zeros(T, rowset * (size + 1)), sizeof(T) * (size + 1)

function fetch!(source::ODBC.Source)
    stmt = source.stmt
    source.status = ODBC.API.SQLFetchScroll(stmt, ODBC.API.SQL_FETCH_NEXT, 0)
    source.rowsfetched[] == 0 && return
    types = source.jltypes
    for col = 1:length(types)
        ODBC.cast!(types[col], source, col)
    end
    return
end

function booleanize!(ind::Vector{ODBC.API.SQLLEN}, new::Vector{Bool}, len)
    @simd for i = 1:len
        @inbounds new[i] = ind[i] == ODBC.API.SQL_NULL_DATA
    end
    return new
end

# primitive types
function cast!{T}(::Type{T}, source::ODBC.Source, col::Integer)
    len = source.rowsfetched[]
    if Data.isdone(source)
        isnull = Vector{Bool}(len)
        booleanize!(source.indcols[col], isnull, len)
        source.columns[col] = NullableArray{T,1}(resize!(source.boundcols[col], len), isnull)
    else
        dest = NullableArray(T, len)
        ccall(:memcpy, Void, (Ptr{T}, Ptr{T}, Csize_t), pointer(dest.values), pointer(source.boundcols[col]), len * sizeof(T))
        booleanize!(source.indcols[col], dest.isnull, len)
        source.columns[col] = dest
    end
    return
end

# decimal/numeric and binary types
using DecFP
const DECZERO = Dec64(0)

cast(::Type{Dec64}, arr::Array, cur::Integer, ind::Integer) = ind <= 0 ? DECZERO : parse(Dec64, String(unsafe_wrap(Array, pointer(arr, cur), ind)))

function cast!(::Type{Dec64}, source::Source, col::Integer)
    len = source.rowsfetched[]
    values = Vector{Dec64}(len)
    isnull = Vector{Bool}(len)
    cur = 1
    elsize = source.sizes[col] + 1
    @inbounds for x = 1:len
        ind = source.indcols[col][x]
        values[x] = cast(Dec64, source.boundcols[col], cur, ind)
        isnull[x] = ind == ODBC.API.SQL_NULL_DATA
        cur += elsize
    end
    source.columns[col] = NullableArray{Dec64,1}(values, isnull)
    return
end

cast(::Type{Vector{UInt8}}, arr::Array, cur::Integer, ind::Integer) = arr[cur:(cur + max(ind, 0) - 1)]

function cast!(::Type{Vector{UInt8}}, source::Source, col::Integer)
    len = source.rowsfetched[]
    values = Vector{Vector{UInt8}}(len)
    isnull = Vector{Bool}(len)
    cur = 1
    elsize = source.sizes[col] + 1
    @inbounds for x = 1:len
        ind = source.indcols[col][x]
        values[x] = cast(Vector{UInt8}, source.boundcols[col], cur, ind)
        isnull[x] = ind == ODBC.API.SQL_NULL_DATA
        cur += elsize
    end
    source.columns[col] = NullableArray{Vector{UInt8},1}(values, isnull)
    return
end

# string types
bytes2codeunits(::Type{UInt8},  bytes) = ifelse(bytes == ODBC.API.SQL_NULL_DATA, 0, Int(bytes))
bytes2codeunits(::Type{UInt16}, bytes) = ifelse(bytes == ODBC.API.SQL_NULL_DATA, 0, Int(bytes >> 1))
bytes2codeunits(::Type{UInt32}, bytes) = ifelse(bytes == ODBC.API.SQL_NULL_DATA, 0, Int(bytes >> 2))
codeunits2bytes(::Type{UInt8},  bytes) = ifelse(bytes == ODBC.API.SQL_NULL_DATA, 0, Int(bytes))
codeunits2bytes(::Type{UInt16}, bytes) = ifelse(bytes == ODBC.API.SQL_NULL_DATA, 0, Int(bytes * 2))
codeunits2bytes(::Type{UInt32}, bytes) = ifelse(bytes == ODBC.API.SQL_NULL_DATA, 0, Int(bytes * 4))

function cast!(::Type{String}, source::Source, col::Integer)
    len = source.rowsfetched[]
    data = source.boundcols[col]
    T = eltype(data)
    isnull = Vector{Bool}(len)
    cur = 1
    elsize = source.sizes[col] + 1
    values = Vector{String}(len)
    @inbounds for i in 1:len
        indic = source.indcols[col][i]
        isnull[i] = indic == ODBC.API.SQL_NULL_DATA
        length = ODBC.bytes2codeunits(T, max(indic, 0))
        values[i] = length == 0 ? "" : String(transcode(UInt8, data[cur:(cur + length - 1)]))
        cur += elsize
    end
    source.columns[col] = NullableArray{String,1}(values, isnull)
    return
end

function cast!{T}(::Type{WeakRefString{T}}, source::Source, col::Integer)
    len = source.rowsfetched[]
    lens = Vector{Int}(len)
    isnull = Vector{Bool}(len)
    parent = Vector{UInt8}()
    cur = 1
    elsize = source.sizes[col] + 1
    @inbounds for i = 1:len
        indic = source.indcols[col][i]
        lens[i] = length = ODBC.bytes2codeunits(T, max(indic, 0))
        isnull[i] = indic == ODBC.API.SQL_NULL_DATA
        append!(parent, reinterpret(UInt8, source.boundcols[col][cur:(cur + length - 1)])) # is append already doing a copy here?
        cur += elsize
    end
    values = Vector{WeakRefString{T}}(len)
    ind = 1
    @inbounds for (i, length) in enumerate(lens)
        values[i] = length == 0 ? WeakRefString{T}(Ptr{T}(0), 0, 0) : WeakRefString{T}(pointer(parent, ind), length, ind)
        ind += ODBC.codeunits2bytes(T, length)
    end
    source.columns[col] = NullableArray{WeakRefString{T},1}(values, isnull, parent)
    return
end

# long types
const LONG_DATA_BUFFER_SIZE = 1024

function cast!{T}(::Type{ODBC.API.Long{T}}, source::Source, col::Integer)
    eT = eltype(source.boundcols[col])
    stmt = source.stmt
    data = Vector{UInt8}()
    buf = zeros(UInt8, ODBC.LONG_DATA_BUFFER_SIZE)
    ind = Ref{ODBC.API.SQLLEN}()
    res = ODBC.API.SQLGetData(stmt, col, source.ctypes[col], pointer(buf), length(buf), ind)
    isnull = ind[] == ODBC.API.SQL_NULL_DATA
    while !isnull
        len = ind[]
        oldlen = length(data)
        resize!(data, oldlen + len)
        ccall(:memcpy, Void, (Ptr{Void}, Ptr{Void}, Csize_t), pointer(data, oldlen + 1), pointer(buf), len)
        res = ODBC.API.SQLGetData(stmt, col, source.ctypes[col], pointer(buf), length(buf), ind)
        res != ODBC.API.SQL_SUCCESS && res != ODBC.API.SQL_SUCCESS_WITH_INFO && break
    end
    d = transcode(UInt8, reinterpret(eT, data))
    source.columns[col] = NullableArray{T,1}([T(d)], [isnull])
end

# DataStreams interface
Data.schema(source::ODBC.Source, ::Type{Data.Column}) = source.schema
"Checks if an `ODBC.Source` has finished fetching results from an executed query string"
function Data.isdone(source::ODBC.Source, x::Integer=1, y::Integer=1)
    return source.status != ODBC.API.SQL_SUCCESS && source.status != ODBC.API.SQL_SUCCESS_WITH_INFO
end

Data.streamtype{T<:ODBC.Source}(::Type{T}, ::Type{Data.Column}) = true
Data.streamtype{T<:ODBC.Source}(::Type{T}, ::Type{Data.Field}) = true

function Data.streamfrom{T}(source::ODBC.Source, ::Type{Data.Field}, ::Type{Nullable{T}}, row, col)
    val = source.columns[col][row - source.rowoffset]::Nullable{T}
    if col == length(source.columns) && (row - source.rowoffset) == length(source.columns[col]) && !Data.isdone(source)
        ODBC.fetch!(source)
        source.rowoffset += source.rowsfetched[]
    end
    return val
end

function Data.streamfrom{T}(source::ODBC.Source, ::Type{Data.Column}, ::Type{NullableVector{T}}, col)
    dest = source.columns[col]::NullableVector{T}
    if col == length(source.columns) && !Data.isdone(source)
        ODBC.fetch!(source)
    end
    return dest
end

function query(
    source::ODBC.Source,
    sink::Any = DataFrame,
    args...;
    append::Bool=false,
    transforms::Dict=Dict{Int, Function}()
)
    sink = Data.stream!(source, sink, append, transforms, args...)
    Data.close!(sink)
    return sink
end

function query(statement::Statement, args...; weakrefstrings::Bool=true, kwargs...)
    source = Source(statement; weakrefstrings=weakrefstrings)
    return query(source, args...; kwargs...)
end

function query(
    statement::Statement,
    values::Union{Array, Tuple},
    args...;
    weakrefstrings::Bool=true,
    kwargs...
)
    source = Source(statement, values; weakrefstrings=weakrefstrings)
    return query(source, args...; kwargs...)
end

function query(dsn::DSN, sql::AbstractString, args...; weakrefstrings::Bool=true, kwargs...)
    source = Source(dsn, sql; weakrefstrings=weakrefstrings)
    return query(source, args...; kwargs...)
end

"Convenience string macro for executing an SQL statement against a DSN."
macro sql_str(s,dsn)
    query(dsn,s)
end
