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
    @static if Sys.iswindows()
        driver_prompt = prompt ? ODBC.API.SQL_DRIVER_PROMPT : ODBC.API.SQL_DRIVER_NOPROMPT
        window_handle = prompt ? ccall((:GetForegroundWindow, :user32), Ptr{Void}, () ) : C_NULL
    else
        driver_prompt = ODBC.API.SQL_DRIVER_NOPROMPT
        window_handle = C_NULL
    end
    out_conn = Block(ODBC.API.SQLWCHAR, BUFLEN)
    out_buff = Ref{Int16}()
    @CHECK dbc ODBC.API.SQL_HANDLE_DBC ODBC.API.SQLDriverConnect(dbc, window_handle, conn_string, out_conn.ptr, BUFLEN, out_buff, driver_prompt)
    connection_string = string(out_conn, out_buff[])
    return connection_string
end

"`ODBC.prepare` prepares an SQL statement to be executed"
function prepare(dsn::DSN, query::AbstractString)
    stmt = ODBCAllocHandle(ODBC.API.SQL_HANDLE_STMT, dsn.dbc_ptr)
    ODBC.@CHECK stmt ODBC.API.SQL_HANDLE_STMT ODBC.API.SQLPrepare(stmt, query)
    return Statement(dsn, stmt, query, Task(1))
end

cast(x) = x
cast(x::Date) = ODBC.API.SQLDate(x)
cast(x::DateTime) = ODBC.API.SQLTimestamp(x)
cast(x::String) = WeakRefString(pointer(x), sizeof(x))

getpointer(::Type{T}, A, i) where {T} = unsafe_load(Ptr{Ptr{Void}}(pointer(A, i)))
getpointer(::Type{WeakRefString{T}}, A, i) where {T} = convert(Ptr{Void}, A[i].ptr)
getpointer(::Type{String}, A, i) = convert(Ptr{Void}, pointer(Vector{UInt8}(A[i])))

sqllength(x) = 1
sqllength(x::AbstractString) = length(x)
sqllength(x::Vector{UInt8}) = length(x)
sqllength(x::ODBC.API.SQLDate) = 10
sqllength(x::Union{ODBC.API.SQLTime,ODBC.API.SQLTimestamp}) = length(string(x))

clength(x) = 1
clength(x::AbstractString) = length(x)
clength(x::Vector{UInt8}) = length(x)
clength(x::WeakRefString{T}) where {T} = codeunits2bytes(T, x.len)
clength(x::CategoricalArrays.CategoricalValue) = length(String(x))
clength(x::Null) = ODBC.API.SQL_NULL_DATA

digits(x) = 0
digits(x::ODBC.API.SQLTimestamp) = length(string(x.fraction * 1000000))

function execute!(statement::Statement, values)
    stmt = statement.stmt
    values2 = Any[cast(x) for x in values]
    pointers = Ptr[]
    types = map(typeof, values2)
    for (i, v) in enumerate(values2)
        if isnull(v)
            ODBC.@CHECK stmt ODBC.API.SQL_HANDLE_STMT ODBC.API.SQLBindParameter(stmt, i, ODBC.API.SQL_PARAM_INPUT,
                ODBC.API.SQL_C_CHAR, ODBC.API.SQL_CHAR, 0, 0, C_NULL, 0, Ref(ODBC.API.SQL_NULL_DATA))
        else
            ctype, sqltype = ODBC.API.julia2C[types[i]], ODBC.API.julia2SQL[types[i]]
            csize, len, dgts = sqllength(v), clength(v), digits(v)
            ptr = getpointer(types[i], values2, i)
            # println("ctype: $ctype, sqltype: $sqltype, digits: $dgts, len: $len, csize: $csize")
            push!(pointers, ptr)
            ODBC.@CHECK stmt ODBC.API.SQL_HANDLE_STMT ODBC.API.SQLBindParameter(stmt, i, ODBC.API.SQL_PARAM_INPUT,
                ctype, sqltype, csize, dgts, ptr, len, Ref(len))
        end
    end
    execute!(statement)
    return
end

function execute!(statement::Statement)
    stmt = statement.stmt
    ODBC.@CHECK stmt ODBC.API.SQL_HANDLE_STMT ODBC.API.SQLExecute(stmt)
    return
end

"`ODBC.execute!` is a minimal method for just executing an SQL `query` string. No results are checked for or returned."
function execute!(dsn::DSN, query::AbstractString, stmt=dsn.stmt_ptr)
    ODBC.ODBCFreeStmt!(stmt)
    ODBC.@CHECK stmt ODBC.API.SQL_HANDLE_STMT ODBC.API.SQLExecDirect(stmt, query)
    return
end

"""
`ODBC.Source` constructs a valid `Data.Source` type that executes an SQL `query` string for the `dsn` ODBC DSN.
Results are checked for and an `ODBC.ResultBlock` is allocated to prepare for fetching the resultset.
"""
function Source(dsn::DSN, query::AbstractString; weakrefstrings::Bool=true, noquery::Bool=false)
    stmt = dsn.stmt_ptr
    noquery || ODBC.ODBCFreeStmt!(stmt)
    supportsreset = ODBC.API.SQLSetStmtAttr(stmt, ODBC.API.SQL_ATTR_CURSOR_SCROLLABLE, ODBC.API.SQL_SCROLLABLE, ODBC.API.SQL_IS_INTEGER)
    supportsreset &= ODBC.API.SQLSetStmtAttr(stmt, ODBC.API.SQL_ATTR_CURSOR_TYPE, ODBC.API.SQL_CURSOR_STATIC, ODBC.API.SQL_IS_INTEGER)
    noquery || (ODBC.@CHECK stmt ODBC.API.SQL_HANDLE_STMT ODBC.API.SQLExecDirect(stmt, query))
    rows, cols = Ref{Int}(), Ref{Int16}()
    ODBC.API.SQLNumResultCols(stmt, cols)
    ODBC.API.SQLRowCount(stmt, rows)
    rows, cols = rows[], cols[]
    #Allocate arrays to hold each column's metadata
    cnames = Array{String}(cols)
    ctypes, csizes = Array{ODBC.API.SQLSMALLINT}(cols), Array{ODBC.API.SQLULEN}(cols)
    cdigits, cnulls = Array{ODBC.API.SQLSMALLINT}(cols), Array{ODBC.API.SQLSMALLINT}(cols)
    juliatypes = Array{Type}(cols)
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
        ctypes[x], csizes[x], cdigits[x], cnulls[x] = t, csize[], digits[], null[]
        alloctypes[x], juliatypes[x], longtexts[x] = ODBC.API.SQL2Julia[t]
        longtext |= longtexts[x]
    end
    if !weakrefstrings
        foreach(i->juliatypes[i] <: Union{WeakRefString, Null} && setindex!(juliatypes, Union{String, Null}, i), 1:length(juliatypes))
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
    boundcols = Array{Any}(cols)
    indcols = Array{Vector{ODBC.API.SQLLEN}}(cols)
    for x = 1:cols
        if longtexts[x]
            boundcols[x], indcols[x] = alloctypes[x][], ODBC.API.SQLLEN[]
        else
            boundcols[x], elsize = internal_allocate(alloctypes[x], rowset, csizes[x])
            indcols[x] = Array{ODBC.API.SQLLEN}(rowset)
            ODBC.API.SQLBindCols(stmt, x, ODBC.API.SQL2C[ctypes[x]], pointer(boundcols[x]), elsize, indcols[x])
        end
    end
    columns = ((allocate(T) for T in juliatypes)...)
    schema = Data.Schema(juliatypes, cnames, rows,
        Dict("types"=>[ODBC.API.SQL_TYPES[c] for c in ctypes], "sizes"=>csizes, "digits"=>cdigits, "nulls"=>cnulls))
    rowsfetched = Ref{ODBC.API.SQLLEN}() # will be populated by call to SQLFetchScroll
    ODBC.API.SQLSetStmtAttr(stmt, ODBC.API.SQL_ATTR_ROWS_FETCHED_PTR, rowsfetched, ODBC.API.SQL_NTS)
    types = [ODBC.API.SQL2C[ctypes[x]] for x = 1:cols]
    source = ODBC.Source(schema, dsn, query, columns, 100, rowsfetched, 0, boundcols, indcols, csizes, types, Type[longtexts[x] ? ODBC.API.Long{T} : T for (x, T) in enumerate(juliatypes)], supportsreset == 1)
    rows != 0 && fetch!(source)
    return source
end

# primitive types
allocate(::Type{T}) where {T} = Vector{T}(0)
allocate(::Type{Union{Null, WeakRefString{T}}}) where {T} = WeakRefStringArray(UInt8[], Union{Null, WeakRefString{T}}, 0)

internal_allocate(::Type{T}, rowset, size) where {T} = Vector{T}(rowset), sizeof(T)
# string/binary types
internal_allocate(::Type{T}, rowset, size) where {T <: Union{UInt8, UInt16, UInt32}} = zeros(T, rowset * (size + 1)), sizeof(T) * (size + 1)

function fetch!(source)
    stmt = source.dsn.stmt_ptr
    source.status = ODBC.API.SQLFetchScroll(stmt, ODBC.API.SQL_FETCH_NEXT, 0)
    # source.rowsfetched[] == 0 && return
    # types = source.jltypes
    # for col = 1:length(types)
    #     ODBC.cast!(types[col], source, col)
    # end
    return
end

# primitive types
function cast!(::Type{T}, source, col) where {T}
    len = source.rowsfetched[]
    c = source.columns[col]
    resize!(c, len)
    ind = source.indcols[col]
    data = source.boundcols[col]
    @simd for i = 1:len
        @inbounds c[i] = ifelse(ind[i] == ODBC.API.SQL_NULL_DATA, null, data[i])
    end
    return c
end

# decimal/numeric and binary types
using DecFP

cast(::Type{Dec64}, arr, cur, ind) = ind <= 0 ? DECZERO : parse(Dec64, String(unsafe_wrap(Array, pointer(arr, cur), ind)))

function cast!(::Type{Union{Dec64, Null}}, source, col)
    len = source.rowsfetched[]
    c = source.columns[col]
    resize!(c, len)
    cur = 1
    elsize = source.sizes[col] + 1
    inds = source.indcols[col]
    @inbounds for i = 1:len
        ind = inds[i]
        c[i] = ind == ODBC.API.SQL_NULL_DATA ? null : cast(Dec64, source.boundcols[col], cur, ind)
        cur += elsize
    end
    return c
end

cast(::Type{Vector{UInt8}}, arr, cur, ind) = arr[cur:(cur + max(ind, 0) - 1)]

function cast!(::Type{Union{Vector{UInt8}, Null}}, source, col)
    len = source.rowsfetched[]
    c = source.columns[col]
    resize!(c, len)
    cur = 1
    elsize = source.sizes[col] + 1
    inds = source.indcols[col]
    @inbounds for i = 1:len
        ind = inds[i]
        c[i] = ind == ODBC.API.SQL_NULL_DATA ? null : cast(Vector{UInt8}, source.boundcols[col], cur, ind)
        cur += elsize
    end
    return c
end

# string types
bytes2codeunits(::Type{UInt8},  bytes) = ifelse(bytes == ODBC.API.SQL_NULL_DATA, 0, Int(bytes))
bytes2codeunits(::Type{UInt16}, bytes) = ifelse(bytes == ODBC.API.SQL_NULL_DATA, 0, Int(bytes >> 1))
bytes2codeunits(::Type{UInt32}, bytes) = ifelse(bytes == ODBC.API.SQL_NULL_DATA, 0, Int(bytes >> 2))
codeunits2bytes(::Type{UInt8},  bytes) = ifelse(bytes == ODBC.API.SQL_NULL_DATA, 0, Int(bytes))
codeunits2bytes(::Type{UInt16}, bytes) = ifelse(bytes == ODBC.API.SQL_NULL_DATA, 0, Int(bytes * 2))
codeunits2bytes(::Type{UInt32}, bytes) = ifelse(bytes == ODBC.API.SQL_NULL_DATA, 0, Int(bytes * 4))

function cast!(::Type{Union{String, Null}}, source, col)
    len = source.rowsfetched[]
    c = source.columns[col]
    resize!(c, len)
    data = source.boundcols[col]
    T = eltype(data)
    cur = 1
    elsize = source.sizes[col] + 1
    inds = source.indcols[col]
    @inbounds for i in 1:len
        ind = inds[i]
        length = ODBC.bytes2codeunits(T, max(ind, 0))
        c[i] = ind == ODBC.API.SQL_NULL_DATA ? null : (length == 0 ? "" : String(transcode(UInt8, data[cur:(cur + length - 1)])))
        cur += elsize
    end
    return c
end

function cast!(::Type{Union{WeakRefString{T}, Null}}, source, col) where {T}
    len = source.rowsfetched[]
    c = source.columns[col]
    resize!(c, len)
    empty!(c.data)
    data = copy(source.boundcols[col])
    push!(c.data, data)
    cur = 1
    elsize = source.sizes[col] + 1
    inds = source.indcols[col]
    EMPTY = WeakRefString{T}(Ptr{T}(0), 0)
    @inbounds for i = 1:len
        ind = inds[i]
        length = ODBC.bytes2codeunits(T, max(ind, 0))
        c[i] = ind == ODBC.API.SQL_NULL_DATA ? null : (length == 0 ? EMPTY : WeakRefString{T}(pointer(data, cur), length))
        cur += elsize
    end
    return c
end

# long types
const LONG_DATA_BUFFER_SIZE = 1024

function cast!(::Type{ODBC.API.Long{Union{T, Null}}}, source, col) where {T}
    stmt = source.dsn.stmt_ptr
    eT = eltype(source.boundcols[col])
    data = eT[]
    buf = zeros(eT, ODBC.LONG_DATA_BUFFER_SIZE)
    ind = Ref{ODBC.API.SQLLEN}()
    res = ODBC.API.SQLGetData(stmt, col, source.ctypes[col], pointer(buf), sizeof(buf), ind)
    isnull = ind[] == ODBC.API.SQL_NULL_DATA
    while !isnull
        len = ind[]
        oldlen = length(data)
        resize!(data, oldlen + bytes2codeunits(eT, len))
        ccall(:memcpy, Void, (Ptr{Void}, Ptr{Void}, Csize_t), pointer(data, oldlen + 1), pointer(buf), len)
        res = ODBC.API.SQLGetData(stmt, col, source.ctypes[col], pointer(buf), length(buf), ind)
        res != ODBC.API.SQL_SUCCESS && res != ODBC.API.SQL_SUCCESS_WITH_INFO && break
    end
    c = source.columns[col]
    resize!(c, 1)
    c[1] = isnull ? null : T(transcode(UInt8, data))
    return c
end

# DataStreams interface
Data.schema(source::ODBC.Source) = source.schema
"Checks if an `ODBC.Source` has finished fetching results from an executed query string"
Data.isdone(source::ODBC.Source, x=1, y=1) = source.status != ODBC.API.SQL_SUCCESS && source.status != ODBC.API.SQL_SUCCESS_WITH_INFO
function Data.reset!(source::ODBC.Source)
    source.supportsreset || throw(ArgumentError("Data.reset! not supported, probably due to the database vendor ODBC driver implementation"))
    stmt = source.dsn.stmt_ptr
    source.status = ODBC.API.SQLFetchScroll(stmt, ODBC.API.SQL_FETCH_FIRST, 0)
    source.rowoffset = 0
    return
end

Data.streamtype(::Type{ODBC.Source}, ::Type{Data.Column}) = true
Data.streamtype(::Type{ODBC.Source}, ::Type{Data.Field}) = true

function Data.streamfrom(source::ODBC.Source, ::Type{Data.Field}, ::Type{Union{T, Null}}, row, col) where {T}
    val = source.columns[col][row - source.rowoffset]::Union{T, Null}
    if col == length(source.columns) && (row - source.rowoffset) == source.rowsfetched[] && !Data.isdone(source)
        ODBC.fetch!(source)
        for i = 1:col
            cast!(source.jltypes[i], source, i)
        end
        source.rowoffset += source.rowsfetched[]
    end
    return val
end

function Data.streamfrom(source::ODBC.Source, ::Type{Data.Column}, ::Type{Union{T, Null}}, row, col) where {T}
    dest = cast!(source.jltypes[col], source, col)
    if col == length(source.columns) && !Data.isdone(source)
        ODBC.fetch!(source)
    end
    return dest
end

function query(dsn::DSN, sql::AbstractString, sink=DataFrame, args...; weakrefstrings::Bool=true, append::Bool=false, transforms::Dict=Dict{Int,Function}())
    sink = Data.stream!(Source(dsn, sql; weakrefstrings=weakrefstrings), sink, args; append=append, transforms=transforms)
    return Data.close!(sink)
end

function query(dsn::DSN, sql::AbstractString, sink::T; weakrefstrings::Bool=true, append::Bool=false, transforms::Dict=Dict{Int,Function}()) where {T}
    sink = Data.stream!(Source(dsn, sql; weakrefstrings=weakrefstrings), sink; append=append, transforms=transforms)
    return Data.close!(sink)
end

query(source::ODBC.Source, sink=DataFrame, args...; append::Bool=false, transforms::Dict=Dict{Int,Function}()) = (sink = Data.stream!(source, sink, args...; append=append, transforms=transforms); return Data.close!(sink))
query(source::ODBC.Source, sink::T; append::Bool=false, transforms::Dict=Dict{Int,Function}()) where {T} = (sink = Data.stream!(source, sink; append=append, transforms=transforms); return Data.close!(sink))

"Convenience string macro for executing an SQL statement against a DSN."
macro sql_str(s,dsn)
    query(dsn,s)
end
