function ODBCAllocHandle(handletype, parenthandle)
    handle = Array(Ptr{Void},1)
    if @FAILED SQLAllocHandle(handletype,parenthandle,handle)
        error("[ODBC]: ODBC Handle Allocation Failed; Return Code: $ret")
    else
        handle = handle[1]
        if handletype == SQL_HANDLE_ENV
            if @FAILED SQLSetEnvAttr(handle,SQL_ATTR_ODBC_VERSION,SQL_OV_ODBC3)
                #If version-setting fails, release environment handle and set global ENV variable to a null pointer
                SQLFreeHandle(SQL_HANDLE_ENV,handle)
                global ENV = C_NULL
                error("[ODBC]: Failed to set ODBC version; please restart Julia and try `using ODBC` again; Return Code: $ret")
            end
        end
    end
    return handle
end

# Connect to qualified DSN (pre-established through ODBC Admin), with optional username and password inputs
function ODBCConnect!(dbc::Ptr{Void},dsn::AbstractString,username::AbstractString,password::AbstractString)
    if @FAILED SQLConnect(dbc,dsn,username,password)
        ODBCError(SQL_HANDLE_DBC,dbc)
        error("[ODBC]: SQLConnect failed; Return Code: $ret")
    end
end

# Alternative connect function that allows user to create datasources on the fly through opening the ODBC admin
function ODBCDriverConnect!(dbc::Ptr{Void},conn_string::AbstractString,driver_prompt::UInt16)
    window_handle = C_NULL
    @windows_only window_handle = ccall((:GetForegroundWindow, :user32), Ptr{Void}, () )
    @windows_only driver_prompt = SQL_DRIVER_PROMPT
    out_conn = zeros(SQLWCHAR,1024)
    out_buff = zeros(Int16,1)
    if @FAILED SQLDriverConnect(dbc,window_handle,conn_string,out_conn,out_buff,driver_prompt)
        ODBCError(SQL_HANDLE_DBC,dbc)
        error("[ODBC]: SQLDriverConnect failed; Return Code: $ret")
    end
    return ODBCClean(out_conn,1,out_buff[1])
end

# Send query to DMBS
function ODBCQueryExecute(stmt::Ptr{Void}, querystring::AbstractString)
    if @FAILED SQLExecDirect(stmt, querystring)
        ODBCError(SQL_HANDLE_STMT,stmt)
        error("[ODBC]: SQLExecDirect failed; Return Code: $ret")
    end
end

# Retrieve resultset metadata once query is processed, Metadata type is returned
function ODBCMetadata(stmt::Ptr{Void},querystring::AbstractString)
        #Allocate space for and fetch number of columns and rows in resultset
        cols = Array(Int16,1)
        rows = Array(Int,1)
        ODBC.SQLNumResultCols(stmt,cols)
        ODBC.SQLRowCount(stmt,rows)
        cols = cols[1]
        rows = rows[1]
        #Allocate arrays to hold each column's metadata
        colnames = Array(UTF8String,cols)
        coltypes = Array(Int16,cols)
        colsizes = Array(Int,cols)
        coldigits = Array(Int16,cols)
        colnulls  = Array(Int16,cols)
        #Allocate space for and fetch the name, type, size, etc. for each column
        for x = 1:cols
            column_name = zeros(SQLWCHAR, 256)
            name_length = Array(Int16, 1)
            datatype = Array(Int16, 1)
            column_size = Array(Int, 1)
            decimal_digits = Array(Int16, 1)
            nullable = Array(Int16, 1)
            SQLDescribeCol(stmt, x, column_name, name_length, datatype, column_size, decimal_digits, nullable)
            colnames[x]  = ODBCClean(column_name, 1, name_length[1])
            coltypes[x]  = datatype[1]
            colsizes[x]  = Int(column_size[1])
            coldigits[x] = decimal_digits[1]
            colnulls[x]  = nullable[1]
        end
    return Metadata(querystring, Int(cols[1]), rows[1], colnames, coltypes, colsizes, coldigits, colnulls)
end

# Using resultset metadata, allocate space/arrays for previously generated resultset, retrieve results
function ODBCBindCols(stmt::Ptr{Void},meta::Metadata)
    #with catalog functions or all-filtering WHERE clauses, resultsets can have 0 rows/cols
    meta.rows == 0 && return (Any[],Any[],0)
    rowset = min(ODBC.MULTIROWFETCH,max(meta.rows,1))
    ODBC.SQLSetStmtAttr(stmt, ODBC.SQL_ATTR_ROW_ARRAY_SIZE, UInt(rowset), ODBC.SQL_IS_UINTEGER)
    # these Any arrays are where the ODBC manager dumps result data
    indicator = Array(Any,meta.cols)
    columns = Array(Any,meta.cols)
    for x = 1:meta.cols
        sqltype = meta.coltypes[x][1]
        #we need the C type so the ODBC manager knows how to store the data
        ctype = get(SQL2C,sqltype,SQL_C_CHAR)
        #we need the julia type that corresponds to the C type size
        jtype = get(SQL2Julia,sqltype,UInt8)
        holder, jlsize = ODBCColumnAllocate(jtype,meta.colsizes[x]+1,rowset)
        ind = Array(Int,rowset)
        if @SUCCEEDED ODBC.SQLBindCols(stmt,x,ctype,holder,Int(jlsize),ind)
            columns[x] = holder
            indicator[x] = ind
        else #SQL_ERROR
            ODBCError(SQL_HANDLE_STMT,stmt)
            error("[ODBC]: SQLBindCol $x failed; Return Code: $ret")
        end
    end
    return (columns, indicator, rowset)
end

# ODBCColumnAllocate is used to allocate the raw
# underlying C-type buffers to be bound in SQLBindCol
ODBCColumnAllocate(x,y,z)               = (Array(x,z),sizeof(x))
ODBCColumnAllocate(x::Type{UInt8},y,z)  = (zeros(x,(y,z)),y)
ODBCColumnAllocate(x::Type{UInt16},y,z) = (zeros(x,(y,z)),y*2)
ODBCColumnAllocate(x::Type{UInt32},y,z) = (zeros(x,(y,z)),y*4)

# ODBCAllocate is the Julia type array that the raw underlying C-type buffer
# data is converted to when moved to a DataFrame or written to file
ODBCAllocate(x,y)                  = zeros(eltype(x),y)
ODBCAllocate(x::Array{UInt8,2},y)  = Array(UTF8String,y)
ODBCAllocate(x::Array{UInt16,2},y) = Array(UTF16String,y)
ODBCAllocate(x::Array{UInt32,2},y) = Array(UTF8String,y)

# ODBCClean does any necessary transformations from raw C-type to Julia type
ODBCClean(x,y,z) = x[y]
ODBCClean(x::Array{UInt8},y,z)  = utf8(x[1:z,y])
ODBCClean(x::Array{UInt16},y,z) = utf16(x[1:z,y])
ODBCClean(x::Array{UInt32},y,z) = utf32(x[1:z,y])

function ODBCCopy!(dest,dsto,src,n,ind,nas)
    for i = 1:n
        nas[i+dsto-1] = ind[i] < 0
        dest[i+dsto-1] = src[i]
    end
end

function ODBCCopy!(dest::Array{UTF8String},dsto,src::Array{UInt8,2},n,ind,nas)
    for i = 1:n
        nas[i+dsto-1] = ind[i] < 0
        dest[i+dsto-1] = utf8(bytestring(src[1:ind[i],i]))
    end
end

function ODBCCopy!(dest::Array{UTF16String},dsto,src::Array{UInt16,2},n,ind,nas)
    for i = 1:n
        nas[i+dsto-1] = ind[i] < 0
        raw = src[1:div(ind[i], 2), i]
        str = utf16(convert(Ptr{UInt16}, raw), length(raw))
        dest[i+dsto-1] = str
    end
end

function ODBCCopy!(dest::Array{UTF8String},dsto,src::Array{UInt32},n,ind,nas)
    for i = 1:n
        nas[i+dsto-1] = ind[i] < 0
        dest[i+dsto-1] = utf8(bytestring(convert(Array{UInt8},src[1:div(ind[i],4),i])))
    end
end

#function for fetching a resultset into a DataFrame
function ODBCFetch(stmt::Ptr{Void},meta::Metadata,columns::Vector{Any},rowset,indicator)
    cols = Array(Any,meta.cols)
    nulls = Array(Any,meta.cols)
    for i = 1:meta.cols
        cols[i] = ODBCAllocate(columns[i],meta.rows)
        nulls[i] = Array(Bool,meta.rows)
    end
    rowsfetched = zeros(Int,1)
    SQLSetStmtAttr(stmt,SQL_ATTR_ROWS_FETCHED_PTR,rowsfetched,SQL_NTS)
    r = 1
    while @SUCCEEDED SQLFetchScroll(stmt,SQL_FETCH_NEXT,0)
        rows = rowsfetched[1] < rowset ? rowsfetched[1] : rowset
        for col = 1:meta.cols
            ODBCCopy!(cols[col],r,columns[col],rows,indicator[col],nulls[col])
        end
        r += rows
    end
    for i = 1:meta.cols
        cols[i] = NullableArrays.NullableArray(cols[i],nulls[i])
    end
    return cols
end

function ODBCFetchPush(stmt::Ptr{Void},meta::Metadata,columns::Array{Any,1},rowset::Int,indicator)
    cols = Array(Any,meta.cols)
    nas = Array(BitVector,meta.cols)
    for i = 1:meta.cols
        cols[i] = ODBCAllocate(columns[i],0)
        nas[i] = falses(0)
    end
    rowsfetched = zeros(Int,1)
    SQLSetStmtAttr(stmt,SQL_ATTR_ROWS_FETCHED_PTR,rowsfetched,SQL_NTS)
    while @SUCCEEDED SQLFetchScroll(stmt,SQL_FETCH_NEXT,0)
        rows = rowsfetched[1] < rowset ? rowsfetched[1] : rowset
        for col = 1:meta.cols
            temp = ODBCAllocate(columns[col],rows)
            tempna = falses(rows)
            ODBCCopy!(temp,1,columns[col],rows,indicator[col],tempna)
            append!(cols[col],temp)
            append!(nas[col],tempna)
        end
    end
    cols = Any[DataArray(cols[col],nas[col]) for col = 1:length(cols)]
    resultset = DataFrame(cols, DataFrames.Index(Symbol[DataFrames.identifier(i) for i in meta.colnames]))
end

# writefield takes a Julia value and gets it ready for writing to a file i.e. converts to string
writefield(io,x) = print(io,x)
writefield(io,x::AbstractString) = print(io,'"',x,'"')

function ODBCFetchToFile(stmt::Ptr{Void},meta::Metadata,columns::Array{Any,1},rowset::Int,output::AbstractString,l::Int)
    out_file = l == 0 ? open(output,"w") : open(output,"a")
    write(out_file, join(meta.colnames,delim), '\n')
    while @SUCCEEDED SQLFetchScroll(stmt,SQL_FETCH_NEXT,0)
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
    SQLFreeStmt(stmt,SQL_CLOSE)
    SQLFreeStmt(stmt,SQL_UNBIND)
    SQLFreeStmt(stmt,SQL_RESET_PARAMS)
end

# Takes an SQL handle as input and retrieves any error messages
# associated with that handle; there may be more than one
function ODBCError(handletype::Int16,handle::Ptr{Void})
    i = Int16(1)
    state = zeros(SQLWCHAR,6)
    error_msg = zeros(SQLWCHAR, 1024)
    native = zeros(Int,1)
    msg_length = zeros(Int16,1)
    while @SUCCEEDED SQLGetDiagRec(handletype,handle,i,state,native,error_msg,msg_length)
        st  = ODBCClean(state,1,5)
        msg = ODBCClean(error_msg, 1, msg_length[1])
        println("[ODBC] $st: $msg")
        i = Int16(i+1)
    end
end
