#Check and allocate, if needed, an ODBC environment handle
#TODO: Is there another way to check if environment is valid?
function SQLAllocEnv()
	if env == C_NULL
		global env
		env = c_malloc(4)
		#Allocate environment handle
		return_value = ccall( (:SQLAllocHandle, @odbc), stdcall, 
			Int16, (Int16,Int32,Ptr{Void}),
			SQL_HANDLE_ENV,SQL_NULL_HANDLE,env)
	
		if (return_value == SQL_SUCCESS) || (return_value == SQL_SUCCESS_WITH_INFO)
			#If allocation succeeded, retrieve env pointer stored at env's address
			env = convert(Ptr{Void},pointer_to_array(convert(Ptr{Uint},env),(1,),true)[1])
			#Set environment ODBC version
			return_value = ccall( (:SQLSetEnvAttr, @odbc), stdcall, 
				Int16, (Ptr{Void},Int32,Int32,Int32), 
				env, SQL_ATTR_ODBC_VERSION,SQL_OV_ODBC3,SQL_IS_INTEGER)
	
			if (return_value == SQL_SUCCESS) || (return_value == SQL_SUCCESS_WITH_INFO)
				return
			else #SQL_ERROR
				#If version-setting fails, release environment handle
				ccall( (:SQLFreeHandle, @odbc), stdcall,  
					Int16, (Int16,Ptr{Void}), SQL_HANDLE_ENV,env)
				c_free(env)
				env = null_connection
				error("[ODBC]: Failed to set ODBC version")
			end
		else #SQL_ERROR
			#If allocation fails, free env memory
			c_free(env)
			env = null_connection
			error("[ODBC]: ODBC environment setup failed")
		end
	end
end
#Allocate connection handle
function SQLAllocDbc()
	SQLAllocEnv() #Make sure environment exists
	dbc = c_malloc(4)
	#Allocate connection handle
	return_value = ccall( (:SQLAllocHandle, @odbc), stdcall, 
		Int16, (Int16,Ptr{Void},Ptr{Void}),
		SQL_HANDLE_DBC,env,dbc)
	
	if (return_value == SQL_SUCCESS) || (return_value == SQL_SUCCESS_WITH_INFO)
		#If allocation succeeded, retrieve the connection pointer stored at dbc's address
		dbc = convert(Ptr{Void},pointer_to_array(convert(Ptr{Uint},dbc),(1,),true)[1])
	else #SQL_ERROR
		c_free(dbc)
		ErrorReport(SQL_HANDLE_ENV,env)
		error("[ODBC]: Connection setup failed")
	end
end
#Allocate statement handle
function SQLAllocStmt(dbc::Ptr{Void})
	SQLAllocEnv() #Make sure environment exists
	stmt = c_malloc(4)
	#Allocate statement handle
	return_value = ccall( (:SQLAllocHandle, @odbc), stdcall, 
		Int16, (Int16,Ptr{Void},Ptr{Void}),
		SQL_HANDLE_STMT,dbc,stmt)
	
	if (return_value == SQL_SUCCESS) || (return_value == SQL_SUCCESS_WITH_INFO)
		#If allocation succeeded, retrieve the statement pointer stored at stmt's address
		stmt = convert(Ptr{Void},pointer_to_array(convert(Ptr{Uint},stmt),(1,),true)[1])
	else #SQL_ERROR
		c_free(stmt)
		ErrorReport(SQL_HANDLE_DBC,dbc)
		error("[ODBC]: Statement setup failed")
	end
end
#SQLConnect: Connect to qualified DSN (pre-established through ODBC Admin), with optional username and password inputs
function SQLConnect(dbc::Ptr{Void},dsn::String,username,password)
	if username != C_NULL
		username = bytestring(username)
		userend = SQL_NTS
	else
		#username = C_NULL by default
		userend = 0
	end
	if password != C_NULL
		password = bytestring(password)
		passend = SQL_NTS
	else
		#password = C_NULL by default
		passend = 0
	end
	SQLAllocEnv()
	
	return_value = ccall( (:SQLConnect, @odbc), stdcall, 
		Int16, (Ptr{Void},Ptr{Uint8},Int32,Ptr{Uint8},Int32,Ptr{Uint8},Int32), 
		dbc,bytestring(dsn),SQL_NTS,username,userend,password,passend)
	
	if (return_value == SQL_SUCCESS) || (return_value == SQL_SUCCESS_WITH_INFO)
		return SQL_SUCCESS
	else #SQL_ERROR
		ErrorReport(SQL_HANDLE_DBC,dbc)
		error("[ODBC]: SQLConnect failed")
	end
end
#SQLDriverConnect: Alternative connect function that allows user to create datasources on the fly through opening the ODBC admin
function SQLDriverConnect(dbc::Ptr{Void},conn_string::String)
	window_handle = C_NULL	
	@windows_only window_handle = ccall( (:GetForegroundWindow, "user32"), Ptr{Void}, () )
		
	return_value = ccall( (:SQLDriverConnect, @odbc), stdcall, 
		Int16, (Ptr{Void},Ptr{Void},Ptr{Uint8},Int16,Ptr{Void},Int16,Ptr{Void},Int16),
		dbc,window_handle,bytestring(conn_string),length(conn_string),C_NULL,0,C_NULL,SQL_DRIVER_COMPLETE)
	if (return_value == SQL_SUCCESS) || (return_value == SQL_SUCCESS_WITH_INFO)
		return SQL_SUCCESS
	else #SQL_ERROR
		ErrorReport(SQL_HANDLE_DBC,dbc)
		error("[ODBC]: SQLDriverConnect failed")
	end
end
#QueryExecute: Send query to DBMS and return SQL_SUCCESS (0) when resultset has been generated server-side
function SQLExecDirect(stmt::Ptr{Void},query::String)
	SQLAllocEnv()

	return_value = ccall( (:SQLExecDirect, @odbc), stdcall, 
		Int16, (Ptr{Void},Ptr{Uint8},Int32),
		stmt,bytestring(query),SQL_NTS)
	
	if (return_value == SQL_SUCCESS) || (return_value == SQL_SUCCESS_WITH_INFO)
		return SQL_SUCCESS
	else #SQL_ERROR
		ErrorReport(SQL_HANDLE_STMT,stmt)
		error("[ODBC]: SQLExecDirect failed")
	end
end
#Result Metadata: Retrieve resultset metadata on a previously generated resultset, Metadata type is returned
function ResultMetadata(connection::Connection)
	#Allocate space for and fetch number of columns and rows in resultset
	cols = zeros(Int,1)
	rows = zeros(Int,1)
	ccall( (:SQLNumResultCols, @odbc), stdcall,  Int16, (Ptr{Void},Ptr{Int}), connection.stmt_ptr, cols)
	ccall( (:SQLRowCount, @odbc), stdcall,  Int16, (Ptr{Void},Ptr{Int}), connection.stmt_ptr, rows)
	#Allocate arrays to hold each column's metadata
	colnames = ref(ASCIIString)
	coltypes = ref(Int16)
	colsizes = ref(Int)
	coldigits = ref(Int16)
	colnulls = ref(Int16)
	#Allocate space for and fetch the name, type, size, etc. for reach column
	for x in 1:cols[1]
		column_name = Array(Uint8,256)
		name_length = zeros(Int16,1)
		datatype = zeros(Int16,1)
		column_size = zeros(Int,1)
		decimal_digits = zeros(Int16,1)
		nullable = zeros(Int16,1) 
			
		return_value = ccall( (:SQLDescribeCol, @odbc), stdcall, 
			Int16, (Ptr{Void},Int32,Ptr{Uint8},Int32,Ptr{Int16},Ptr{Int16},Ptr{Int},Ptr{Int16},Ptr{Int16}),
			connection.stmt_ptr,x,column_name,256,name_length,datatype,column_size,decimal_digits,nullable)
			
		push!(colnames,nullstrip(column_name))
		push!(coltypes,datatype[1])
		push!(colsizes,int(column_size[1]))
		push!(coldigits,decimal_digits[1])
		push!(colnulls,nullable[1])
	end
	
	return Metadata("",cols[1],rows[1],colnames,coltypes,colsizes,coldigits,colnulls)
end
#SQLBindCol: Using resultset metadata, allocate space/arrays for previously generated resultset
function SQLBindCols(connection::Connection,meta::Metadata)
	global rowset = MULTIROWFETCH > meta.rows ? meta.rows : MULTIROWFETCH
	ccall( (:SQLSetStmtAttr, @odbc), stdcall, 
		Int16, (Ptr{Void}, Int32, Ptr{Uint}, Int32),
		connection.stmt_ptr,SQL_ATTR_ROW_ARRAY_SIZE, rowset, 0)
	indicator = Array(Int, (rowset,meta.cols))
	columns = ref(Any)
	julia_types = ref(Any)
	#Main numeric types are mapped to appropriate Julia types; all others currently default to strings via Uint8 Arrays
	#Once Julia has a system for passing C structs, we can support native date and timestamp types
	#See the 'consts.jl' file for more information
	for x in 1:meta.cols
		if contains((SQL_BIT,SQL_TINYINT),meta.coltypes[x])
			holder = Array(Int8, rowset)
			return_value = ccall( (:SQLBindCol, @odbc), stdcall, 
				Int16, (Ptr{Void},Int32,Int16,Ptr{Int8},Int,Ptr{Int}),
				connection.stmt_ptr,x,SQL_C_TINYINT,holder,sizeof(Int8),indicator[:,x])
				julia_types = push!(julia_types,Int8)
		elseif meta.coltypes[x] == SQL_SMALLINT
			holder = Array(Int16, rowset)
			return_value = ccall( (:SQLBindCol, @odbc), stdcall, 
				Int16, (Ptr{Void},Int32,Int16,Ptr{Int16},Int,Ptr{Int}),
				connection.stmt_ptr,x,SQL_C_SHORT,holder,sizeof(Int16),indicator[:,x])
				julia_types = push!(julia_types,Int16)
		elseif contains((SQL_REAL,SQL_INTEGER),meta.coltypes[x])
			holder = Array(Int, rowset)
			return_value = ccall( (:SQLBindCol, @odbc), stdcall, 
				Int16, (Ptr{Void},Int32,Int16,Ptr{Int},Int,Ptr{Int}),
				connection.stmt_ptr,x,SQL_C_LONG,holder,sizeof(Int),indicator[:,x])
				julia_types = push!(julia_types,Int)
		elseif meta.coltypes[x] == SQL_BIGINT
			holder = Array(Int64, rowset)
			return_value = ccall( (:SQLBindCol, @odbc), stdcall, 
				Int16, (Ptr{Void},Int32,Int16,Ptr{Int64},Int,Ptr{Int}),
				connection.stmt_ptr,x,SQL_C_BIGINT,holder,sizeof(Int64),indicator[:,x])
				julia_types = push!(julia_types,Int64)
		elseif contains((SQL_DECIMAL,SQL_NUMERIC,SQL_FLOAT,SQL_DOUBLE),meta.coltypes[x])
			holder = Array(Float64, rowset)
			return_value = ccall( (:SQLBindCol, @odbc), stdcall, 
				Int16, (Ptr{Void},Int32,Int16,Ptr{Float64},Int,Ptr{Int}),
				connection.stmt_ptr,x,SQL_C_DOUBLE,holder,sizeof(Float64),indicator[:,x])
				julia_types = push!(julia_types,Float64)
		else
			holder = Array(Uint8, (meta.colsizes[x]+1,rowset))
			return_value = ccall( (:SQLBindCol, @odbc), stdcall, 
				Int16, (Ptr{Void},Int32,Int16,Ptr{Uint8},Int,Ptr{Int}),
				connection.stmt_ptr,x,SQL_C_CHAR,holder,meta.colsizes[x]+1,indicator[:,x])
				julia_types = push!(julia_types,String)
		end
		
		if return_value == SQL_SUCCESS
			columns = push!(columns,holder)
		else #SQL_ERROR
			ErrorReport(SQL_HANDLE_STMT,connection.stmt_ptr)
			error("[ODBC]: SQLBindCol $x failed")
		end
	end
	return columns, julia_types, indicator
end
function SQLFetchScroll(connection::Connection,columns::Array{Any,1},rows::Int,julia_types::Array{Any,1},colnames::Array{ASCIIString,1},colsizes::Array{Int},indicator::Array{Int})
	cols = Array(Any,length(columns))
	for i = 1:length(columns)
		cols[i] = DataArray(julia_types[i],rows)
		for j in 1:rows
		    cols[i][j] = DataFrames.baseval(julia_types[i])
            cols[i][j] = NA
		end
	end
	results = DataFrame(cols, Index(colnames))
	fetchseq = seq(1,rows,rowset)
	for i in fetchseq
		return_value = ccall( (:SQLFetchScroll, @odbc), stdcall, 
			Int16, (Ptr{Void},Int16,Int), 
			connection.stmt_ptr,SQL_FETCH_NEXT,0)
		if (return_value == SQL_SUCCESS) || (return_value == SQL_SUCCESS_WITH_INFO)
			if i == fetchseq[end]
				dfend = rows
				colend = rows - i + 1
			else
				dfend = i+rowset-1		
				colend = rowset
			end
			for j = 1:length(columns)
				if typeof(columns[j]) == Array{Uint8,2}
					results[i:dfend,j] = nullstrip(copy(columns[j][1:colend*(colsizes[j]+1)]),colsizes[j]+1,colend)
				else
					results[i:dfend,j] = copy(columns[j][1:colend])
				end	
			end
		else
			ErrorReport(SQL_HANDLE_STMT,connection.stmt_ptr)
			SQLFreeStmt(connection)
			error("[ODBC]: Fetching results failed")
		end
	end
	SQLFreeStmt(connection)
	return results
end

#SQLFreeStmt: used to 'clear' a statement of bound columns, resultsets, and other bound parameters in preparation for a subsequent query
function SQLFreeStmt(connection::Connection)
	return_value = ccall( (:SQLFreeStmt, @odbc), stdcall, 
		Int16, (Ptr{Void},Uint16), connection.stmt_ptr, SQL_CLOSE)
	return_value = ccall( (:SQLFreeStmt, @odbc), stdcall, 
		Int16, (Ptr{Void},Uint16), connection.stmt_ptr, SQL_UNBIND)
	return_value = ccall( (:SQLFreeStmt, @odbc), stdcall, 
		Int16, (Ptr{Void},Uint16), connection.stmt_ptr, SQL_RESET_PARAMS)
end
#String Helper Function: String buffers are allocated for 256 characters, after data is fetched,
#this function strips out all the unused buffer space and converts Array{Uint8} to Julia string
function nullstrip(string::Array{Uint8})
	if ndims(string) == 2
		string = string[1:end]
	end
	bytes = search(bytestring(string),"\0")[1] - 1
	bytestring(string[1:bytes])
end
function nullstrip(stringblob, colsize::Real, rowset::Real)
	a = DataArray(String,rowset)
	n = 1
	for i in seq(1,length(stringblob),colsize)
		a[n] = nullstrip(stringblob[i:i+colsize-1])
		if a[n] == "" a[n] = NA end
		n+=1
	end
	return a
end
#Senquence function similar to R's seq() though without as many options
function seq(start::Real,stop::Real,by::Int)
	(start, stop) = promote(start, stop)
	T = typeof(start)
	if by == 0
		len = length(start:stop)
		a = Array(T, len)
		for i = start:stop
			a[i] = i
		end
	else
		len = ifloor(stop/int(by)) + (mod(stop,by) > 0 ? 1 : 0)
		a = Array(T, len)
		for i = 1:len
			a[i] = start + by*(i-1)
		end
	end
		return a
end
seq(start::Real,stop::Real) = seq(start::Real,stop::Real,0)
#Error Reporting: Takes an SQL handle as input and retrieves any error messages associated with that handle; there may be more than one
function ErrorReport(handletype::Int,handle::Ptr{Void})
	state = Array(Uint8,7)
	error_msg = Array(Uint8, 1024)
	native = Array(Int,1)
	i = int16(1)
	msg_length = Array(Int16,1)
	return_value = SQL_SUCCESS
	
	while return_value == SQL_SUCCESS
	return_value = ccall( (:SQLGetDiagRecA, @odbc), stdcall, 
		Int16, (Int16,Ptr{Void},Int16,Ptr{Uint8},Ptr{Int},Ptr{Uint8},Int16,Ptr{Int16}),
		int16(handletype),handle,i,state,native,error_msg,256,msg_length)
		st = nullstrip(state)
		msg = nullstrip(error_msg)
		if return_value == SQL_SUCCESS
			println("Driver Error:$msg")
			i+=1
		end
	end
end
