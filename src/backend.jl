function ODBCAllocHandle(handletype, parenthandle)
    handle = Ref{Ptr{Void}}()
    ODBC.API.SQLAllocHandle(handletype,parenthandle,handle)
    handle = handle[]
    if handletype == ODBC.API.SQL_HANDLE_ENV
        ODBC.API.SQLSetEnvAttr(handle,ODBC.API.SQL_ATTR_ODBC_VERSION,ODBC.API.SQL_OV_ODBC3)
    end
    return handle
end

# Alternative connect function that allows user to create datasources on the fly through opening the ODBC admin
function ODBCDriverConnect!(dbc::Ptr{Void},conn_string,driver_prompt::UInt16)
    window_handle = C_NULL
    @windows_only window_handle = ccall((:GetForegroundWindow, :user32), Ptr{Void}, () )
    @windows_only driver_prompt = ODBC.API.SQL_DRIVER_PROMPT
    out_conn = Block(ODBC.API.SQLWCHAR,BUFLEN)
    out_buff = Ref{Int16}()
    @CHECK dbc ODBC.API.SQL_HANDLE_DBC ODBC.API.SQLDriverConnect(dbc,window_handle,conn_string,out_conn.ptr,BUFLEN,out_buff,driver_prompt)
    connection_string = string(out_conn,out_buff[])
    free!(out_conn)
    return connection_string
end

function execute!(dsn::DSN, query::AbstractString)
    stmt = dsn.stmt_ptr
    ODBC.ODBCFreeStmt!(stmt)
    ODBC.@CHECK stmt ODBC.API.SQL_HANDLE_STMT ODBC.API.SQLExecDirect(stmt, query)
    return
end

# independent Source constructor
function Source(dsn::DSN, query::AbstractString)
    stmt = dsn.stmt_ptr
    ODBC.ODBCFreeStmt!(stmt)
    ODBC.@CHECK stmt ODBC.API.SQL_HANDLE_STMT ODBC.API.SQLExecDirect(stmt, query)
    rows, cols = Ref{Int}(), Ref{Int16}()
    ODBC.API.SQLNumResultCols(stmt,cols)
    ODBC.API.SQLRowCount(stmt,rows)
    rows, cols = rows[], cols[]
    #Allocate arrays to hold each column's metadata
    cnames = Array(UTF8String,cols)
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
        cnames[x] = string(cname, len[])
        t = dt[]
        ctypes[x], csizes[x], cdigits[x], cnulls[x] = t, csize[], digits[], null[]
        alloctypes[x], juliatypes[x], islongtext = ODBC.API.SQL2Julia[t]
        longtext |= islongtext
    end
    ODBC.free!(cname)
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
    if rows != 0
        for x = 1:cols
            block = ODBC.Block(alloctypes[x], rowset, csizes[x]+1)
            ind = Array(ODBC.API.SQLLEN,rowset)
            ODBC.API.SQLBindCols(stmt,x,ODBC.API.SQL2C[ctypes[x]],block.ptr,block.elsize,ind)
            columns[x], indcols[x] = block, ind
        end
    end
    schema = Data.Schema(cnames, juliatypes, rows,
        Dict("types"=>ctypes, "sizes"=>csizes, "digits"=>cdigits, "nulls"=>cnulls))
    rowsfetched = Ref{ODBC.API.SQLLEN}() # will be populated by call to SQLFetchScroll
    ODBC.API.SQLSetStmtAttr(stmt,ODBC.API.SQL_ATTR_ROWS_FETCHED_PTR,rowsfetched,ODBC.API.SQL_NTS)
    rb = ODBC.ResultBlock(columns,indcols,juliatypes,rowset,rowsfetched)
    return ODBC.Source(schema,dsn,query,rb,ODBC.API.SQLFetchScroll(stmt,ODBC.API.SQL_FETCH_NEXT,0))
end

# Fetch Strategies
  #1. Reinterpet Blocks that were allocated and bound
  #2. Copy allocated and bound Blocks to pre-allocated output and reinterpret final output
  #3. Grow output by rows fetched, copy allocated and bound Blocks to newly grown output, reinterpret final output
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

Data.isdone(source::ODBC.Source) = source.status != ODBC.API.SQL_SUCCESS && source.status != ODBC.API.SQL_SUCCESS_WITH_INFO

# fetch data from the result of a query
function Data.stream!(source::ODBC.Source, ::Type{Data.Table})
    rb = source.rb;
    rows, cols = size(source)
    if rb.fetchsize == rows
        # fetch strategy #1: reinterpret allocated Blocks
        data = Array(NullableVector, cols)
        other = []
        for col = 1:cols
            data[col] = NullableArray(rb.jltypes[col],rb.columns[col],rb.indcols[col],rows)
            push!(other, rb.columns[col])
        end
        return Data.Table(Data.schema(source),data,other)
    else
        # fetch strategy #2 or #3
        dt = Data.Table(Data.header(source), Data.types(source), max(0,rows));
        return Data.stream!(source, dt)
    end
end

function Data.stream!(source::ODBC.Source, dt::Data.Table)
    rb = source.rb;
    rows, cols = size(source)
    data = dt.data;
    other = []
    dt.other = other
    r = 0
    while true
        rowsfetched = rb.rowsfetched[]
        rowsfetched == 0 && break
        if rows < 0
            # fetch strategy #3: grow our output and copy Blocks to new output space until done
            for col = 1:cols
                ODBC.append!(rb.jltypes[col],rb.columns[col],rb.indcols[col],data[col],r,rowsfetched,other)
            end
        else
            # fetch strategy #2: copy allocated Blocks to pre-allocated output
            for col = 1:cols
                #TODO: add a check that we have enough space to copy rowsfetched into data[col] from r
                ODBC.copy!(rb.jltypes[col],rb.columns[col],rb.indcols[col],data[col],r,rowsfetched,other)
            end
        end
        r += rowsfetched
        Data.isdone(source) && break
        source.status = ODBC.API.SQLFetchScroll(source.dsn.stmt_ptr,ODBC.API.SQL_FETCH_NEXT,0)
    end
    for col = 1:cols
        free!(rb.columns[col])
    end
    source.schema.rows = dt.schema.rows = r
    return dt
end

function Data.stream!(source::ODBC.Source, sink::CSV.Sink;header::Bool=true)
    header && CSV.writeheaders(source,sink)
    rb = source.rb
    null = sink.options.null
    rows, cols = size(source)
    r = 0
    while true
        rowsfetched = rb.rowsfetched[]
        for row = 1:rowsfetched, col = 1:cols
            ind = rb.indcols[col][row]
            val = getfield(rb.jltypes[col], rb.columns[col], row, ind)
            CSV.writefield(sink, ind == ODBC.API.SQL_NULL_DATA ? null : val, col, cols)
        end
        r += rowsfetched
        Data.isdone(source) && break
        source.status = ODBC.API.SQLFetchScroll(source.dsn.stmt_ptr,ODBC.API.SQL_FETCH_NEXT,0)
    end
    for col = 1:cols
        free!(rb.columns[col])
    end
    source.schema.rows = r
    sink.schema = source.schema
    close(sink)
    return sink
end

function getbind!{T}(jltype::T,block::Block,ind,row,col,stmt)
    val = getfield(jltype, block, row, ind)::T
    if ind == ODBC.API.SQL_NULL_DATA
        SQLite.bind!(stmt,col,SQLite.NULL)
    else
        SQLite.bind!(stmt,col,val)
    end
end

function Data.stream!(source::ODBC.Source, sink::SQLite.Sink)
    rb = source.rb
    rows, cols = size(source)
    stmt = sink.stmt
    handle = stmt.handle
    SQLite.transaction(sink.db) do
        r = 0
        while true
            rowsfetched = source.rowsfetched[]
            for row = 1:rowsfetched
                for col = 1:cols
                    getbind!(rb.jltypes[col],rb.columns[col],rb.indcols[col][row],row,col,stmt)
                end
                SQLite.sqlite3_step(handle)
                SQLite.sqlite3_reset(handle)
            end
            r += rows
            Data.isdone(source) && break
            source.status = ODBC.API.SQLFetchScroll(source.dsn.stmt_ptr,ODBC.API.SQL_FETCH_NEXT,0)
        end
    end
    for col = 1:cols
        free!(rb.columns[col])
    end
    SQLite.execute!(sink.db,"analyze $(sink.tablename)")
    return sink
end

function query(dsn::DSN, querystring::AbstractString, sink=Data.Table)
    source = ODBC.Source(dsn, querystring)
    return Data.stream!(source, sink)
end

# sql"..." string literal for convenience;
# it doesn't do anything different than query right now,
# but we could potentially do some interesting things here
macro sql_str(s)
    query(s)
end

# Replaces backticks in the query string with escaped quotes
# for convenience in using "" in column names, etc.
macro query(x)
    :(query(replace($x, '`', '\"')))
end
