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
    return string(out_conn)
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
    rows = max(0,rows) # in cases where the ODBC driver returns a negative # for rows
    rowset = rows == 0 ? ODBC.API.MAXFETCHSIZE : min(ODBC.API.MAXFETCHSIZE,rows)
    bigquery = rows > ODBC.API.MAXFETCHSIZE || rows == 0
    ODBC.API.SQLSetStmtAttr(stmt, ODBC.API.SQL_ATTR_ROW_ARRAY_SIZE, rowset, ODBC.API.SQL_IS_UINTEGER)
    #Allocate arrays to hold each column's metadata
    cnames = Array(UTF8String,cols)
    ctypes, csizes = Array(ODBC.API.SQLSMALLINT,cols), Array(ODBC.API.SQLULEN,cols)
    cdigits, cnulls = Array(ODBC.API.SQLSMALLINT,cols), Array(ODBC.API.SQLSMALLINT,cols)
    juliatypes = Array(DataType,cols)
    indcols = Array(Vector{ODBC.API.SQLLEN},cols)
    columns = Array(ODBC.Block,cols)
    #Allocate space for and fetch the name, type, size, etc. for each column
    len, dt, csize = Ref{ODBC.API.SQLSMALLINT}(), Ref{ODBC.API.SQLSMALLINT}(), Ref{ODBC.API.SQLULEN}()
    digits, null = Ref{ODBC.API.SQLSMALLINT}(), Ref{ODBC.API.SQLSMALLINT}()
    cname = ODBC.Block(ODBC.API.SQLWCHAR, ODBC.BUFLEN)
    for x = 1:cols
        ODBC.API.SQLDescribeCol(stmt, x, cname.ptr, ODBC.BUFLEN, len, dt, csize, digits, null)
        cnames[x]  = string(cname, len[])
        t = dt[]
        ctypes[x], csizes[x], cdigits[x], cnulls[x] = t, csize[], digits[], null[]
        atype, juliatypes[x] = ODBC.API.SQL2Julia[t]
        block = ODBC.Block(atype, csizes[x]+1, rowset, bigquery || atype <: ODBC.CHARS)
        ind = Array(ODBC.API.SQLLEN,rowset)
        ODBC.API.SQLBindCols(stmt,x,ODBC.API.SQL2C[t],block.ptr,block.elsize,ind)
        columns[x], indcols[x] = block, ind
    end
    schema = Data.Schema(cnames, juliatypes, rows,
        Dict("types"=>ctypes, "sizes"=>csizes, "digits"=>cdigits, "nulls"=>cnulls))
    rb = ODBC.ResultBlock(columns,indcols,rowset)
    rowsfetched = Ref{ODBC.API.SQLLEN}()
    ODBC.API.SQLSetStmtAttr(stmt,ODBC.API.SQL_ATTR_ROWS_FETCHED_PTR,rowsfetched,ODBC.API.SQL_NTS)
    return ODBC.Source(schema,dsn,query,rb,ODBC.API.SQLFetchScroll(stmt,ODBC.API.SQL_FETCH_NEXT,0),rowsfetched)
end

Data.isdone(source::ODBC.Source) = source.status != ODBC.API.SQL_SUCCESS

function Data.stream!(source::ODBC.Source, ::Type{Data.Table};force_append::Bool=false)
    rb = source.rb
    if rb.fetchsize == ODBC.API.MAXFETCHSIZE || size(source,1) == 0 || force_append
        force_append && (source.schema.rows = 0)
        # big query where we'll need to fetch multiple times
        # or when the DBMS didn't return the # of rows, so we need to `append!``
        dt = Data.Table(Data.schema(source))
        return Data.stream!(source, dt)
    else
        # small query where we only needed to fetch once
        rows, cols = size(source)
        data = Array(NullableVector, cols)
        other = []
        for col = 1:cols
            data[col] = NullableArray(rb.columns[col],rb.indcols[col],rows,other)
        end
        return Data.Table(Data.schema(source),data,other)
    end
end

function Data.stream!(source::ODBC.Source, dt::Data.Table)
    rb = source.rb
    data = dt.data
    other = []
    dt.other = other
    rows, cols = size(source)
    if rows == 0
        # DBMS didn't return # of rows, so we just need to keep appending
        r = 0
        while !Data.isdone(source)
            rows = source.rowsfetched[]
            for col = 1:cols
                ODBC.append!(rb.columns[col],rb.indcols[col],data[col],rows,other)
            end
            source.status = ODBC.API.SQLFetchScroll(source.dsn.stmt_ptr,ODBC.API.SQL_FETCH_NEXT,0)
            r += rows
        end
        source.schema.rows = dt.schema.rows = r
    else
        # number of rows known and `dt` is pre-allocated, just need to fill it in
        r = 0
        while !Data.isdone(source)
            rows = source.rowsfetched[]
            for col = 1:cols
                ODBC.copy!(rb.columns[col],rb.indcols[col],data[col],r,rows,other)
            end
            r += rows
            source.status = ODBC.API.SQLFetchScroll(source.dsn.stmt_ptr,ODBC.API.SQL_FETCH_NEXT,0)
        end
    end
    return dt
end

function getfield{T}(source::ODBC.Source, ::Type{T}, row, col)

end

function getfield{T<:CHARS}(source::ODBC.Source, ::Type{T}, row, col)

end

function Data.stream!(source::ODBC.Source, sink::CSV.Sink;header::Bool=true)
    header && CSV.writeheaders(source,sink)
    rb = source.rb
    if rb.fetchsize == ODBC.API.MAXFETCHSIZE
        # big query where we'll need to fetch multiple times
        dt = Data.Table(Data.schema(source))
        return Data.stream!(source, dt)
    else
        # small query where we only needed to fetch once
        rows, cols = size(source)
        other = []
        for row = 1:rows, col = 1:cols
            val =
            CSV.writefield(sink, rb.indcols[col][row] == ODBC.API.SQL_NULL_DATA ? sink.null : val, col, cols)
        end
        return Data.Table(Data.schema(source),data,other)
    end

    rb = source.rb
    data = dt.data
    other = []
    rows, cols = size(source)
    r = 0
    while !Data.isdone(source)
        rows = source.rowsfetched[]
        for col = 1:cols
            ODBC.copy!(rb.columns[col],rb.indcols[col],data[col],r,rows,other)
        end
        r += rows
        source.status = ODBC.API.SQLFetchScroll(source.dsn.stmt_ptr,ODBC.API.SQL_FETCH_NEXT,0)
    end
    return dt
end


# writefield takes a Julia value and gets it ready for writing to a file i.e. converts to string
writefield(io,x) = print(io,x)
writefield(io,x::AbstractString) = print(io,'"',x,'"')

function ODBCFetchToFile(stmt::Ptr{Void},meta,columns::Array{Any,1},rowset::Int,output::AbstractString,l::Int)
    out_file = l == 0 ? open(output,"w") : open(output,"a")
    write(out_file, join(meta.colnames,','), '\n')
    while SQLFetchScroll(stmt,SQL_FETCH_NEXT,0) == SQL_SUCCESS
        for row = 1:rowset, col = 1:meta.cols
            writefield(out_file,ODBCClean(columns[col],row))
            write(out_file, col == meta.cols ? '\n' : ',')
        end
    end
    close(out_file)
    return Any[]
end
