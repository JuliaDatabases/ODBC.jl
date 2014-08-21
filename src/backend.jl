function ODBCAllocHandle(handletype, parenthandle)
    handle = Array(Ptr{Void},1)
    if @FAILED SQLAllocHandle(handletype,parenthandle,handle)
        error("[ODBC]: ODBC Handle Allocation Failed; Return Code: $ret")
    else        
        #If allocation succeeded, retrieve handle pointer stored in handle's array index 1
        handle = handle[1]
        if handletype == SQL_HANDLE_ENV 
            if @FAILED SQLSetEnvAttr(handle,SQL_ATTR_ODBC_VERSION,SQL_OV_ODBC3)
                #If version-setting fails, release environment handle and set global env variable to a null pointer
                SQLFreeHandle(SQL_HANDLE_ENV,handle)
                global env = C_NULL
                error("[ODBC]: Failed to set ODBC version; Return Code: $ret")
            end
        end
    end
    return handle
end

# Connect to qualified DSN (pre-established through ODBC Admin), with optional username and password inputs
function ODBCConnect!(dbc::Ptr{Void},dsn::String,username::String,password::String)
    if @FAILED SQLConnect(dbc,dsn,username,password)
        ODBCError(SQL_HANDLE_DBC,dbc)
        error("[ODBC]: SQLConnect failed; Return Code: $ret")
    end
end

# Alternative connect function that allows user to create datasources on the fly through opening the ODBC admin
function ODBCDriverConnect!(dbc::Ptr{Void},conn_string::String,driver_prompt::Uint16)
    window_handle = C_NULL    
    @windows_only window_handle = ccall((:GetForegroundWindow, :user32), Ptr{Void}, () )
    @windows_only driver_prompt = SQL_DRIVER_PROMPT
    out_buff = Array(Int16,1)
    if @FAILED SQLDriverConnect(dbc,window_handle,conn_string,C_NULL,out_buff,driver_prompt)
        ODBCError(SQL_HANDLE_DBC,dbc)
        error("[ODBC]: SQLDriverConnect failed; Return Code: $ret")
    end
end

# Send query to DMBS
function ODBCQueryExecute(stmt::Ptr{Void}, querystring::String)
    if @FAILED SQLExecDirect(stmt, utf16(querystring))
        ODBCError(SQL_HANDLE_STMT,stmt)
        error("[ODBC]: SQLExecDirect failed; Return Code: $ret")
    end
end

# Retrieve resultset metadata once query is processed, Metadata type is returned
function ODBCMetadata(stmt::Ptr{Void},querystring::String)
        #Allocate space for and fetch number of columns and rows in resultset
        cols = Array(Int16,1)
        rows = Array(Int,1)
        SQLNumResultCols(stmt,cols)
        SQLRowCount(stmt,rows)
        #Allocate arrays to hold each column's metadata
        colnames = UTF8String[]
        coltypes = Array((String,Int16),0)
        colsizes = Int[]
        coldigits = Int16[]
        colnulls  = Int16[]
        #Allocate space for and fetch the name, type, size, etc. for each column
        for x = 1:cols[1]
            column_name = zeros(Uint8,256)
            name_length = Array(Int16,1)
            datatype = Array(Int16,1)
            column_size = Array(Uint,1)
            decimal_digits = Array(Int16,1)
            nullable = Array(Int16,1) 
            SQLDescribeCol(stmt,x,column_name,name_length,datatype,column_size,decimal_digits,nullable)
            push!(colnames,ODBCClean(column_name,1,name_length[1]))
            push!(coltypes,(get(SQL_TYPES,int(datatype[1]),"SQL_CHAR"),datatype[1]))
            push!(colsizes,int(column_size[1]))
            push!(coldigits,decimal_digits[1])
            push!(colnulls,nullable[1])
        end
    return Metadata(querystring,int(cols[1]),rows[1],colnames,coltypes,colsizes,coldigits,colnulls)
end

# [Using resultset metadata, allocate space/arrays for previously generated resultset, retrieve results
function ODBCBindCols(stmt::Ptr{Void},meta::Metadata)
    #with catalog functions or all-filtering WHERE clauses, resultsets can have 0 rows/cols
    meta.rows == 0 && return (Any[],Any[],0)
    rowset = MULTIROWFETCH > meta.rows ? (meta.rows < 0 ? 1 : meta.rows) : MULTIROWFETCH
    SQLSetStmtAttr(stmt,SQL_ATTR_ROW_ARRAY_SIZE,uint(rowset),SQL_IS_UINTEGER)
    
    # these Any arrays are where the ODBC manager dumps result data
    indicator = Any[]
    columns = Any[]
    for x = 1:meta.cols
        sqltype = meta.coltypes[x][2]
        #we need the C type so the ODBC manager knows how to store the data
        ctype = get(SQL2C,sqltype,SQL_C_CHAR)
        #we need the julia type that corresponds to the C type size
        jtype = get(SQL2Julia,sqltype,Uint8)
        holder, jlsize = ODBCColumnAllocate(jtype,meta.colsizes[x]+1,rowset)
        ind = Array(Int,rowset)
        if @SUCCEEDED ODBC.SQLBindCols(stmt,x,ctype,holder,int(jlsize),ind)
            push!(columns,holder)
            push!(indicator,ind)
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
ODBCColumnAllocate(x::Type{Uint8},y,z)  = (zeros(x,(y,z)),y)
ODBCColumnAllocate(x::Type{Uint16},y,z) = (zeros(x,(y,z)),y*2)
ODBCColumnAllocate(x::Type{Uint32},y,z) = (zeros(x,(y,z)),y*4)

# ODBCAllocate is the Julia type array that the raw underlying C-type buffer
# data is converted to when moved to a DataFrame or written to file
ODBCAllocate(x,y)                        = zeros(eltype(typeof(x)),y)
ODBCAllocate(x::Array{Uint8,2},y)        = Array(UTF8String,y)
ODBCAllocate(x::Array{Uint16,2},y)       = Array(UTF16String,y)
ODBCAllocate(x::Array{Uint32,2},y)       = Array(UTF8String,y)
ODBCAllocate(x::Array{SQLDate,1},y)      = Array(Date,y)
ODBCAllocate(x::Array{SQLTime,1},y)      = Array(SQLTime,y)
ODBCAllocate(x::Array{SQLTimestamp,1},y) = Array(DateTime,y)

# ODBCClean does any necessary transformations from raw C-type to Julia type
ODBCClean(x,y,z) = x[y]
ODBCClean(x::Array{Uint8},y,z)          = bytestring(x[1:z,y])
ODBCClean(x::Array{Uint16},y,z)         = UTF16String(x[1:z,y])
ODBCClean(x::Array{Uint32},y,z)         = bytestring(convert(Array{Uint8},x[1:z,y]))
ODBCClean(x::Array{SQLDate,1},y,z)      = date(x[y].year,0 < x[y].month < 13 ? x[y].month : 1,x[y].day)
ODBCClean(x::Array{SQLTimestamp,1},y,z) = 
    DateTime(int64(x[y].year),int64(0 < x[y].month < 13 ? x[y].month : 1),int64(x[y].day),
             int64(x[y].hour),int64(x[y].minute),int64(x[y].second),int64(div(x[y].fraction,1000000)))

function ODBCCopy!(dest,dsto,src,n,ind,nas)
    for i = 1:n
        nas[i+dsto-1] = ind[i] < 0
        dest[i+dsto-1] = src[i]
    end
end

function ODBCCopy!(dest::Array{UTF8String},dsto,src::Array{Uint8,2},n,ind,nas)
    for i = 1:n
        nas[i+dsto-1] = ind[i] < 0
        dest[i+dsto-1] = utf8(bytestring(src[1:ind[i],i]))
    end
end

function ODBCCopy!(dest::Array{UTF16String},dsto,src::Array{Uint16,2},n,ind,nas)
    for i = 1:n
        nas[i+dsto-1] = ind[i] < 0
        raw = src[1:div(ind[i], 2), i]
        str = utf16(convert(Ptr{Uint16}, raw), length(raw))
        dest[i+dsto-1] = str 
    end
end

function ODBCCopy!(dest::Array{UTF8String},dsto,src::Array{Uint32},n,ind,nas)
    for i = 1:n
        nas[i+dsto-1] = ind[i] < 0
        dest[i+dsto-1] = utf8(bytestring(convert(Array{Uint8},src[1:div(ind[i],4),i])))
    end
end

function ODBCCopy!{D<:Date}(dest::Array{D},dsto,src::Array{SQLDate},n,ind,nas)
    for i = 1:n
        nas[i+dsto-1] = ind[i] < 0
        dest[i+dsto-1] = Date(int64(src[i].year),
                              int64(0 < src[i].month < 13 ? src[i].month : 1),
                              int64(src[i].day))
    end
end

function ODBCCopy!{D<:DateTime}(dest::Array{D},dsto,src::Array{SQLTimestamp},n,ind,nas)
    for i = 1:n
        nas[i+dsto-1] = ind[i] < 0
        dest[i+dsto-1] = 
            DateTime(int64(src[i].year),
                     int64(0 < src[i].month < 13 ? src[i].month : 1),
                     int64(src[i].day),
                     int64(src[i].hour),
                     int64(src[i].minute),
                     int64(src[i].second),
                     int64(div(src[i].fraction, 1000000)))
    end
end

function ODBCCopy!(dest::Array{SQLTime},dsto,src::Array{SQLTime},n,ind,nas)
    for i = 1:n
        nas[i+dsto-1] = ind[i] < 0
        dest[i+dsto-1] = src[i]
    end
end

# ODBCEscape takes a Julia value and gets it ready for writing to a file i.e. converts to string
ODBCEscape(x) = string(x)
ODBCEscape(x::String) = "\"$x\""

#function for fetching a resultset into a DataFrame
function ODBCFetchDataFrame(stmt::Ptr{Void},meta::Metadata,columns::Array{Any,1},rowset::Int,indicator)
    tic()
    cols = Array(Any,meta.cols)
    nas = Array(BitVector,meta.cols)
    for i = 1:meta.cols
        cols[i] = ODBCAllocate(columns[i],meta.rows)
        nas[i] = falses(meta.rows)
    end
    rowsfetched = zeros(Int,1)
    SQLSetStmtAttr(stmt,SQL_ATTR_ROWS_FETCHED_PTR,rowsfetched,SQL_NTS)
    r = 1
    while @SUCCEEDED SQLFetchScroll(stmt,SQL_FETCH_NEXT,0)
        rows = rowsfetched[1] < rowset ? rowsfetched[1] : rowset
        for col = 1:meta.cols
            ODBCCopy!(cols[col],r,columns[col],rows,indicator[col],nas[col])
        end
        r += rows
    end
    toc()
    cols = {DataArray(cols[col],nas[col]) for col = 1:length(cols)}
    resultset = DataFrame(cols, DataFrames.Index(Symbol[DataFrames.identifier(i) for i in meta.colnames]))
end

function ODBCFetchDataFramePush!(stmt::Ptr{Void},meta::Metadata,columns::Array{Any,1},rowset::Int,indicator)
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
    cols = {DataArray(cols[col],nas[col]) for col = 1:length(cols)}
    resultset = DataFrame(cols, DataFrames.Index(Symbol[DataFrames.identifier(i) for i in meta.colnames]))
end

function ODBCDirectToFile(stmt::Ptr{Void},meta::Metadata,columns::Array{Any,1},rowset::Int,output::String,delim::Char,l::Int)
    out_file = l == 0 ? open(output,"w") : open(output,"a")
    write(out_file,join(meta.colnames,delim)*"\n")
    while @SUCCEEDED SQLFetchScroll(stmt,SQL_FETCH_NEXT,0)
        for row = 1:rowset, col = 1:meta.cols
            write(out_file,ODBCEscape(ODBCClean(columns[col],row)))
            write(out_file,delim)
            col == meta.cols && write(out_file,"\n")
        end
    end
    close(out_file)
    return DataFrame()
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
    i = int16(1)
    state = zeros(Uint8,6)
    error_msg = zeros(Uint8, 1024)
    native = zeros(Int,1)
    msg_length = zeros(Int16,1)
    while @SUCCEEDED SQLGetDiagRec(handletype,handle,i,state,native,error_msg,msg_length)
        st  = ODBCClean(state,1,5)
        msg = ODBCClean(error_msg, 1, msg_length[1])
        println("[ODBC] $st: $msg")
        i = int16(i+1)
    end
end
