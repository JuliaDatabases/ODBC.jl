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
function ODBCDriverConnect!(dbc::Ptr{Void},conn_string::AbstractString,driver_prompt::UInt16)
    window_handle = C_NULL
    @windows_only window_handle = ccall((:GetForegroundWindow, :user32), Ptr{Void}, () )
    @windows_only driver_prompt = ODBC.API.SQL_DRIVER_PROMPT
    out_conn = zeros(ODBC.API.SQLWCHAR,1024)
    out_buff = zeros(Int16,1)
    @CHECK dbc ODBC.API.SQL_HANDLE_DBC ODBC.API.SQLDriverConnect(dbc,window_handle,conn_string,out_conn,out_buff,driver_prompt)
    return ODBCClean(out_conn,1,out_buff[1])
end

const COLUMN_NAME_BUFFER = zeros(ODBC.API.SQLWCHAR, 1024)
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
    rowset = min(ODBC.API.MAXFETCHSIZE,max(rows,1))
    bigquery = rows > ODBC.API.MAXFETCHSIZE
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
    for x = 1:cols
        ODBC.API.SQLDescribeCol(stmt, x, ODBC.COLUMN_NAME_BUFFER, len, dt, csize, digits, null)
        cnames[x]  = ODBC.ODBCClean(ODBC.COLUMN_NAME_BUFFER, 1, len[])
        t = dt[]
        ctypes[x], csizes[x], cdigits[x], cnulls[x] = t, csize[], digits[], null[]
        atype, juliatypes[x] = ODBC.API.SQL2Julia[t]
        block = ODBC.Block(atype, csizes[x]+1, rowset, false) # bigquery || atype <: ODBC.CHARS
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

function Data.stream!(source::ODBC.Source, ::Type{Data.Table})
    rb = source.rb
    if rb.fetchsize == ODBC.API.MAXFETCHSIZE
        # big query where we'll need to fetch multiple times
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

# ODBCClean does any necessary transformations from raw C-type to Julia type
ODBCClean(x,y,z) = x[y]
ODBCClean(x::Array{UInt8},y,z)  = utf8(x[1:z,y])
ODBCClean(x::Array{UInt16},y,z) = utf16(x[1:z,y])
ODBCClean(x::Array{UInt32},y,z) = utf32(x[1:z,y])

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

# used to 'clear' a statement of bound columns, resultsets,
# and other bound parameters in preparation for a subsequent query
function ODBCFreeStmt!(stmt)
    ODBC.API.SQLFreeStmt(stmt,ODBC.API.SQL_CLOSE)
    ODBC.API.SQLFreeStmt(stmt,ODBC.API.SQL_UNBIND)
    ODBC.API.SQLFreeStmt(stmt,ODBC.API.SQL_RESET_PARAMS)
end
