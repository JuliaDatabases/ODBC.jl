"Allocate ODBC handles for interacting with the ODBC Driver Manager"
function ODBCAllocHandle(handletype, parenthandle)
    handle = Ref{Ptr{Void}}()
    ODBC.API.SQLAllocHandle(handletype,parenthandle,handle)
    handle = handle[]
    if handletype == ODBC.API.SQL_HANDLE_ENV
        ODBC.API.SQLSetEnvAttr(handle,ODBC.API.SQL_ATTR_ODBC_VERSION,ODBC.API.SQL_OV_ODBC3)
    end
    return handle
end

"Alternative connect function that allows user to create datasources on the fly through opening the ODBC admin"
function ODBCDriverConnect!(dbc::Ptr{Void},conn_string,driver_prompt::UInt16)
    window_handle = C_NULL
    @static if is_windows()
        window_handle = ccall((:GetForegroundWindow, :user32), Ptr{Void}, () )
        driver_prompt = ODBC.API.SQL_DRIVER_PROMPT
    end
    out_conn = Block(ODBC.API.SQLWCHAR,BUFLEN)
    out_buff = Ref{Int16}()
    @CHECK dbc ODBC.API.SQL_HANDLE_DBC ODBC.API.SQLDriverConnect(dbc,window_handle,conn_string,out_conn.ptr,BUFLEN,out_buff,driver_prompt)
    connection_string = String(out_conn,out_buff[])
    # free!(out_conn)
    return connection_string
end

"`ODBC.execute!` is a minimal method for just executing an SQL `query` string. No results are checked for or returned."
function execute!(dsn::DSN, query::AbstractString)
    stmt = dsn.stmt_ptr
    ODBC.ODBCFreeStmt!(stmt)
    ODBC.@CHECK stmt ODBC.API.SQL_HANDLE_STMT ODBC.API.SQLExecDirect(stmt, query)
    return
end

"""
`ODBC.Source` constructs a valid `Data.Source` type that executes an SQL `query` string for the `dsn` ODBC DSN.
Results are checked for and an `ODBC.ResultBlock` is allocated to prepare for fetching the resultset.
"""
function Source(dsn::DSN, query::AbstractString)
    stmt = dsn.stmt_ptr
    ODBC.ODBCFreeStmt!(stmt)
    ODBC.@CHECK stmt ODBC.API.SQL_HANDLE_STMT ODBC.API.SQLExecDirect(stmt, query)
    rows, cols = Ref{Int}(), Ref{Int16}()
    ODBC.API.SQLNumResultCols(stmt,cols)
    ODBC.API.SQLRowCount(stmt,rows)
    rows, cols = rows[], cols[]
    #Allocate arrays to hold each column's metadata
    cnames = Array(String,cols)
    ctypes, csizes = Array(ODBC.API.SQLSMALLINT,cols), Array(ODBC.API.SQLULEN,cols)
    cdigits, cnulls = Array(ODBC.API.SQLSMALLINT,cols), Array(ODBC.API.SQLSMALLINT,cols)
    juliatypes = Array(DataType,cols)
    alloctypes = Array(DataType,cols)
    indcols = Array(Vector{ODBC.API.SQLLEN},cols)
    columns = Array(ODBC.Block,cols)
    longtext = false
    #Allocate space for and fetch the name, type, size, etc. for each column
    len, dt, csize = Ref{ODBC.API.SQLSMALLINT}(), Ref{ODBC.API.SQLSMALLINT}(), Ref{ODBC.API.SQLULEN}()
    digits, null = Ref{ODBC.API.SQLSMALLINT}(), Ref{ODBC.API.SQLSMALLINT}()
    cname = ODBC.Block(ODBC.API.SQLWCHAR, ODBC.BUFLEN)
    for x = 1:cols
        ODBC.API.SQLDescribeCol(stmt, x, cname.ptr, ODBC.BUFLEN, len, dt, csize, digits, null)
        cnames[x] = String(cname, len[])
        t = dt[]
        ctypes[x], csizes[x], cdigits[x], cnulls[x] = t, csize[], digits[], null[]
        alloctypes[x], juliatypes[x], islongtext = ODBC.API.SQL2Julia[t]
        longtext |= islongtext
    end
    # ODBC.free!(cname)
    # Determine fetch strategy
    # rows might be -1 (dbms doesn't return total rows in resultset), 0 (empty resultset), or 1+
    if rows > -1 # known # of rows
        if longtext # longtext column types present in resultset
            rowset = min(1,rows) # in case of rows == 0, empty resultset
            multifetch = rows != 1 # we don't need to multifetch if there's only one row
        else
            if rows < ODBC.API.MAXFETCHSIZE
                rowset = rows # rowset is >= 0 and < MAXFETCHSIZE
                multifetch = false
            else
                rowset = ODBC.API.MAXFETCHSIZE
                multifetch = true
            end
        end
    else
        # unknown # of rows
        multifetch = true
        rowset = longtext ? 1 : ODBC.API.MAXFETCHSIZE
    end
    ODBC.API.SQLSetStmtAttr(stmt, ODBC.API.SQL_ATTR_ROW_ARRAY_SIZE, rowset, ODBC.API.SQL_IS_UINTEGER)
    for x = 1:cols
        block = ODBC.Block(alloctypes[x], rowset, csizes[x]+1)
        ind = Array(ODBC.API.SQLLEN,rowset)
        ODBC.API.SQLBindCols(stmt,x,ODBC.API.SQL2C[ctypes[x]],block.ptr,block.elsize,ind)
        columns[x], indcols[x] = block, ind
    end
    schema = Data.Schema(cnames, juliatypes, rows,
        Dict("types"=>[ODBC.API.SQL_TYPES[c] for c in ctypes], "sizes"=>csizes, "digits"=>cdigits, "nulls"=>cnulls))
    rowsfetched = Ref{ODBC.API.SQLLEN}() # will be populated by call to SQLFetchScroll
    ODBC.API.SQLSetStmtAttr(stmt,ODBC.API.SQL_ATTR_ROWS_FETCHED_PTR,rowsfetched,ODBC.API.SQL_NTS)
    rb = ODBC.ResultBlock(columns,indcols,alloctypes,rowset,rowsfetched)
    return ODBC.Source(schema,cols,dsn,query,rb,ODBC.API.SQLFetchScroll(stmt,ODBC.API.SQL_FETCH_NEXT,0))
end

# Fetch Strategies
  #1. Reinterpet Blocks that were allocated and bound
    # isbits arrays: let Julia take ownership of Block memory; zero out the Block
    # mutable arrays: keep references to Block in `other`
  #2. Copy allocated and bound Blocks to pre-allocated output and reinterpret final output
    # isbits arrays: copy Block memory to dest array, free allocated Blocks
    # mutable arrays: keep references to copied Blocks in `other`; free allocated Blocks
  #3. Grow output by rows fetched, copy allocated and bound Blocks to newly grown output, reinterpret final output
    # isbits arrays: copy Block memory to dest array, free allocated Blocks
    # mutable arrays: keep references to copied Blocks in `other`
# Fetch Strategy Determination
  # if known # of rows and # of rows < MAXFETCHSIZE and no LONGTEXT
    # then set rowset = rows, do one SQLFetchScroll, fetch strategy #1
  # if known # of rows and # of rows > MAXFETCHSIZE and no LONGTEXT
    # then set rowset = MAXFETCHSIZE, do multiple SQLFetchScroll, fetch strategy #2
  # if known # of rows and # of rows < or > MAXFETCHSIZE and LONGTEXT
    # then set rowset = 1, do multiple SQLFetchScroll, fetch strategy #2
  # if unknown # of rows and no LONGTEXT
    # then set rowset = MAXFETCHSIZE, do one or more SQLFetchScroll, fetch strategy #3
  # if unknown # of rows and LONGTEXT
    # then set rowset = 1, do multiple SQLFetchScroll, fetch strategy #3
  # if # of rows = 0 then done

"Checks if an `ODBC.Source` has finished fetching results from an executed query string"
Data.isdone(source::ODBC.Source, x, y) = source.status != ODBC.API.SQL_SUCCESS && source.status != ODBC.API.SQL_SUCCESS_WITH_INFO
# Data.reset!(io::ODBC.Source) = nothing

Data.streamtype{T<:ODBC.Source}(::Type{T}, ::Type{Data.Column}) = true
# Data.streamtype{T<:ODBC.Source}(::Type{T}, ::Type{Data.Field}) = true

# function Data.getfield{T}(source::ODBC.Source, ::Type{T}, row, col)
#     if !isdefined(source.columns, col)
#         source.columns[col] = Data.getcolumn(source, T, col)
#     end
#     return source.columns[col][row]
# end

function booleanize!(ind::Vector{ODBC.API.SQLLEN}, new::Vector{Bool}, len)
    @simd for i = 1:len
        @inbounds new[i] = ind[i] == ODBC.API.SQL_NULL_DATA
    end
    return new
end

# bitstype/immutable types
function Data.getcolumn{T}(source::ODBC.Source, ::Type{T}, i)
    rb = source.rb;
    len = rb.rowsfetched[]
    dest = NullableArray(T, len)
    ccall(:memcpy, Void, (Ptr{T}, Ptr{T}, Csize_t), pointer(dest.values), rb.columns[i].ptr, len * sizeof(T))
    booleanize!(rb.indcols[i], dest.isnull, len)
    if i == source.cols && !Data.isdone(source, 1, 1)
        source.status = ODBC.API.SQLFetchScroll(source.dsn.stmt_ptr, ODBC.API.SQL_FETCH_NEXT, 0)
    end
    return dest
end

# Dec64 type
const DECZERO = Dec64(0)
function cast{T}(::Type{Dec64}, ptr::Ptr{T}, len)
    len <= 0 && return DECZERO
    bytes = unsafe_wrap(Array, ptr, ODBC.bytes2codeunits(T, len))
    str = String(Base.transcode(UInt8, bytes))
    return parse(Dec64, str)
end

"fill a NullableVector by copying the data from a Block that has Dec64 data"
function Data.getcolumn(source::ODBC.Source, ::Type{Dec64}, i)
    rb = source.rb;
    len = rb.rowsfetched[]
    dest = NullableArray(Dec64, len)
    values = dest.values
    isnull = dest.isnull
    cur = rb.columns[i].ptr
    elsize = rb.columns[i].elsize
    for x = 1:len
        @inbounds values[x] = cast(Dec64, cur, rb.indcols[i][x])
        @inbounds isnull[x] = rb.indcols[i][x] == ODBC.API.SQL_NULL_DATA
        cur += elsize
    end
    if i == source.cols && !Data.isdone(source, 1, 1)
        source.status = ODBC.API.SQLFetchScroll(source.dsn.stmt_ptr, ODBC.API.SQL_FETCH_NEXT, 0)
    end
    return dest
end

# String/Vector{UInt8} types
# translate a # of bytes and a code unit type (UInt8, UInt16, UInt32) and return the # of code units; returns 0 if field is null
bytes2codeunits(::Type{UInt8},  bytes) = ifelse(bytes == ODBC.API.SQL_NULL_DATA, 0, Int(bytes))
bytes2codeunits(::Type{UInt16}, bytes) = ifelse(bytes == ODBC.API.SQL_NULL_DATA, 0, Int(bytes >> 1))
bytes2codeunits(::Type{UInt32}, bytes) = ifelse(bytes == ODBC.API.SQL_NULL_DATA, 0, Int(bytes >> 2))

cast{T}(::Type{WeakRefString{T}}, ptr, len, x) = len <= 0 ? WeakRefString{T}(Ptr{T}(0), 0, 0) : WeakRefString{T}(ptr, ODBC.bytes2codeunits(T, len), x)
cast(::Type{Vector{UInt8}}, ptr, len, x) = len <= 0 ? UInt8[] : unsafe_wrap(Array, ptr, len, false)

"fill a NullableVector by copying the data from a Block that has container-type"
function Data.getcolumn{T<:Union{Vector{UInt8},AbstractString}}(source::ODBC.Source, ::Type{T}, i)
    rb = source.rb;
    len = rb.rowsfetched[]
    values = Vector{T}(len)
    isnull = Vector{Bool}(len)
    totalbytes = max(0, len == 1 ? rb.indcols[i][1] : len * rb.columns[i].elsize)
    parent = Vector{UInt8}(totalbytes)
    unsafe_copy!(pointer(parent), convert(Ptr{UInt8}, rb.columns[i].ptr), totalbytes)

    cur = pointer(parent)
    ind = 1
    elsize = rb.columns[i].elsize
    for x = 1:len
        @inbounds values[x] = ODBC.cast(T, cur, rb.indcols[i][x], ind)
        @inbounds isnull[x] = rb.indcols[i][x] == ODBC.API.SQL_NULL_DATA
        cur += elsize
        ind += elsize
    end
    if i == source.cols && !Data.isdone(source, 1, 1)
        source.status = ODBC.API.SQLFetchScroll(source.dsn.stmt_ptr, ODBC.API.SQL_FETCH_NEXT, 0)
    end
    return NullableArray{T,1}(values, isnull, parent)
end

# """
# Stream the results of `source` (if any) to a `DataFrame` type. The `DataFrame` will be allocated according
# to the size of the resultset of the query string.
# """
# function Data.stream!(source::ODBC.Source, ::Type{DataFrame})
#     rb = source.rb;
#     rows, cols = size(source)
#     if rb.fetchsize == rows
#         # fetch strategy #1: reinterpret allocated Blocks
#         data = Array(Any, cols)
#         for col = 1:cols
#             data[col] = NullableArray(rb.jltypes[col],rb.columns[col],rb.indcols[col],rows)
#         end
#         return DataFrame(data, map(Symbol, Data.header(source)))
#     else
#         # fetch strategy #2 or #3
#         df = DataFrame(Data.Schema(Data.header(source), Data.types(source), max(0,rows)))
#         return Data.stream!(source, df)
#     end
# end
#
# "Stream the results of an `ODBC.Source` to a pre-allocated `DataFrame`"
# function Data.stream!(source::ODBC.Source, df::DataFrame)
#     rb = source.rb;
#     rows, cols = size(source)
#     data = df.columns;
#     r = 0
#     while true
#         rowsfetched::ODBC.API.SQLLEN = rb.rowsfetched[]
#         (rowsfetched == 0 || rowsfetched > rb.fetchsize) && break
#         if rows < 0
#             # fetch strategy #3: grow our output and copy Blocks to new output space until done
#             for col = 1:cols
#                 ODBC.append!(rb.jltypes[col],rb.columns[col],rb.indcols[col],data[col],r,rowsfetched)
#             end
#         else
#             # fetch strategy #2: copy allocated Blocks to pre-allocated output
#             for col = 1:cols
#                 #TODO: add a check that we have enough space to copy rowsfetched into data[col] from r
#                 ODBC.copy!(rb.jltypes[col],rb.columns[col],rb.indcols[col],data[col],r,rowsfetched)
#             end
#         end
#         r += rowsfetched
#         Data.isdone(source) && break
#         source.status = ODBC.API.SQLFetchScroll(source.dsn.stmt_ptr,ODBC.API.SQL_FETCH_NEXT,0)
#     end
#     for col = 1:cols
#         free!(rb.columns[col])
#     end
#     source.schema.rows = r
#     return df
# end
#
# function getfield!{T}(jltype::Type{T},block::Block,ind,row,col,cols,sink,null)
#     val = ODBC.getfield(jltype, block, row, ind)
#     CSV.writefield(sink, ind == ODBC.API.SQL_NULL_DATA ? null : val, col, cols)
# end
#
# "Stream the results of an `ODBC.Source` directly to a CSV file, represented by `sink::CSV.Sink`"
# function Data.stream!(source::ODBC.Source, sink::CSV.Sink,header::Bool=true)
#     header && CSV.writeheaders(source,sink)
#     rb = source.rb
#     null = sink.options.null
#     rows, cols = size(source)
#     r = 0
#     while true
#         rowsfetched::ODBC.API.SQLLEN = rb.rowsfetched[]
#         rowsfetched == 0 && break
#         for row = 1:rowsfetched, col = 1:cols
#             ind::ODBC.API.SQLLEN = rb.indcols[col][row]
#             ODBC.getfield!(rb.jltypes[col],rb.columns[col],ind,row,col,cols,sink,null)
#         end
#         r += rowsfetched
#         Data.isdone(source) && break
#         source.status = ODBC.API.SQLFetchScroll(source.dsn.stmt_ptr,ODBC.API.SQL_FETCH_NEXT,0)
#     end
#     for col = 1:cols
#         ODBC.free!(rb.columns[col])
#     end
#     source.schema.rows = r
#     sink.schema = source.schema
#     close(sink)
#     return sink
# end
#
# function getbind!{T}(jltype::Type{T},block::Block,ind,row,col,stmt)
#     val = getfield(jltype, block, row, ind)::T
#     if ind == ODBC.API.SQL_NULL_DATA
#         SQLite.bind!(stmt,col,SQLite.NULL)
#     else
#         SQLite.bind!(stmt,col,val)
#     end
# end
#
# "Stream the results of an `ODBC.Source` directly to an SQLite table, represented by `sink::SQLite.Sink`"
# function Data.stream!(source::ODBC.Source, sink::SQLite.Sink)
#     rb = source.rb
#     rows, cols = size(source)
#     stmt = sink.stmt
#     handle = stmt.handle
#     SQLite.transaction(sink.db) do
#         r = 0
#         while true
#             rowsfetched::ODBC.API.SQLLEN = rb.rowsfetched[]
#             for row = 1:rowsfetched
#                 for col = 1:cols
#                     getbind!(rb.jltypes[col],rb.columns[col],rb.indcols[col][row]::ODBC.API.SQLLEN,row,col,stmt)
#                 end
#                 SQLite.sqlite3_step(handle)
#                 SQLite.sqlite3_reset(handle)
#             end
#             r += rows
#             Data.isdone(source) && break
#             source.status = ODBC.API.SQLFetchScroll(source.dsn.stmt_ptr,ODBC.API.SQL_FETCH_NEXT,0)
#         end
#     end
#     for col = 1:cols
#         free!(rb.columns[col])
#     end
#     SQLite.execute!(sink.db,"analyze $(sink.tablename)")
#     return sink
# end

"""
Convenience method that constructs an `ODBC.Source` and streams the results to `sink`.
`sink` can be any valid `Data.Sink` (`CSV.Sink`,`SQLite.Sink`,etc.) and by default, is a `DataFrame`.
"""
function query(dsn::DSN, querystring::AbstractString, sink=DataFrame)
    source = ODBC.Source(dsn, querystring)
    return Data.stream!(source, sink)
end

"Convenience string macro for executing an SQL statement against a DSN."
macro sql_str(s,dsn)
    query(dsn,s)
end
