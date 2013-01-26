#Connect: Connect to DSN, returns Connection object, also stores Connection information in global default 'conn' object and global 'Connections' connections array
function Connect(dsn::String,username,password)
	global number_of_connections
	global Connections
	global conn
	dsn_number = 0
	SQLAllocEnv()
	dbc = SQLAllocDbc()
	return_value = SQLConnect(dbc,dsn,username,password)
	if return_value == SQL_SUCCESS
		stmt = SQLAllocStmt(dbc)
		for x in 1:length(Connections)
			if (Connections[x].dsn==dsn)
				dsn_number+=1
			end
		end
		conn = Connection(dsn,dsn_number+1,dbc,stmt,null_resultset)
		push!(Connections,conn)
		number_of_connections = length(Connections)
		println("Connection $(conn.number) to $(conn.dsn) successful.")  
	else
		ErrorReport(SQL_HANDLE_DBC,dbc)
		error("[ODBC]: Connection failed")
	end
end
Connect(dsn::String) = Connect(dsn,C_NULL,C_NULL) #Convenience method when username and password are already setup in DSN
#AdvancedConnect
function AdvancedConnect(conn_string::String)
	global number_of_connections
	global Connections
	global conn
	dsn_number = 0
	SQLAllocEnv()
	dbc = SQLAllocDbc()
	return_value = SQLDriverConnect(dbc,conn_string)
	if return_value == SQL_SUCCESS
		stmt = SQLAllocStmt(dbc)
		for x in 1:length(Connections)
			if (Connections[x].dsn==dsn)
				dsn_number+=1
			end
		end
		conn = Connection(dsn,dsn_number+1,dbc,stmt,null_resultset)
		push!(Connections,conn)
		number_of_connections = length(Connections)
		println("Connection $(conn.number) to $(conn.dsn) successful.")  
	else
		ErrorReport(SQL_HANDLE_DBC,dbc)
		error("[ODBC]: Connection failed")
	end
end
AdvancedConnect() = AdvancedConnect(" ")
#Query: Sends query string to DBMS, once executed, resultset metadata is returned, space is allocated, and results are returned
function Query(connection::Connection, query::String) 
	if connection == null_connection
		error("[ODBC]: A valid connection was not specified (and no valid default connection exists)")
	end
	SQLFreeStmt(connection)
	return_value = SQLExecDirect(connection.stmt_ptr,query)
	if return_value == SQL_SUCCESS
		metadata = ResultMetadata(connection)
		#metadata = (cols, rows, colnames, coltypes, colsizes, coldigits, colnulls)
		boundcols = SQLBindCols(connection,metadata[1],metadata[2],metadata[4],metadata[5],metadata[6])
		rawresults = SQLFetchScroll(connection,boundcols[1],metadata[2],boundcols[2],metadata[3],metadata[5])
		connection.results = rawresults
		return rawresults
	else
		ErrorReport(SQL_HANDLE_DBC,connection.dbc_ptr)
		ErrorReport(SQL_HANDLE_STMT,connection.stmt_ptr)
		error("[ODBC]: Query execution failed")
	end
end
Query(query::String) = Query(conn, query) #Convenience method when using default connection 'conn'
#Disconnect:
function Disconnect(connection::Connection)
	global conn
	global Connections
	global number_of_connections
	SQLFreeStmt(connection)
	return_value = ccall( (:SQLDisconnect, @odbc), stdcall,
		Int16, (Ptr{Void},), connection.dbc_ptr)
	c_free(connection.stmt_ptr)
	c_free(connection.dbc_ptr)
	if return_value == SQL_SUCCESS || return_value == SQL_SUCCESS_WITH_INFO
		for x = 1:length(Connections)
			if connection.dsn == Connections[x].dsn && connection.number == Connections[x].number
				delete!(Connections,x)
				if is(conn,connection)
					if length(Connections) != 0
						conn = Connections[end]
					else
						conn = null_connection #Create null default connection
					end
				end
			end
		end
		number_of_connections = length(Connections)
		println("$(connection.dsn) connection number $(connection.number) disconnected successfully")
	else
		ErrorReport(SQL_HANDLE_DBC,connection.dbc_ptr)
		error("[ODBC]: Could not disconnect")
	end
end
Disconnect() = Disconnect(conn)
#List Installed Drivers
function ListDrivers()
	descriptions = ref(String)
	attributes = ref(String)
	driver_desc = Array(Uint8, 256)
	desc_length = Array(Int32, 1)
	driver_attr = Array(Uint8, 256)
	attr_length = Array(Int32, 1)
	return_value = SQL_SUCCESS #Initialization
	while return_value == SQL_SUCCESS || return_value == SQL_SUCCESS_WITH_INFO
		return_value = ccall( (:SQLDrivers, @odbc), stdcall,
			Int16, (Ptr{Void},Int16,Ptr{Uint8},Int32,Ptr{Int32},Ptr{Uint8},Int32,Ptr{Int32}),
			env,SQL_FETCH_NEXT,driver_desc,256,desc_length,driver_attr,256,attr_length)
		if return_value == SQL_SUCCESS || return_value == SQL_SUCCESS_WITH_INFO
			push!(descriptions,nullstrip(driver_desc))
			push!(attributes,nullstrip(driver_attr))
		else
		break
		end
	end
	drivers = [descriptions attributes]
end
#List defined DSNs
function ListDatasources()
	descriptions = ref(String)
	attributes = ref(String)
	dsn_desc = Array(Uint8, 256)
	desc_length = Array(Int32, 1)
	dsn_attr = Array(Uint8, 256)
	attr_length = Array(Int32, 1)
	return_value = SQL_SUCCESS #Initialization
	while return_value == SQL_SUCCESS || return_value == SQL_SUCCESS_WITH_INFO
		return_value = ccall( (:SQLDataSources, @odbc), stdcall,
			Int16, (Ptr{Void},Int16,Ptr{Uint8},Int32,Ptr{Int32},Ptr{Uint8},Int32,Ptr{Int32}),
			env,SQL_FETCH_NEXT,dsn_desc,256,desc_length,dsn_attr,256,attr_length)
		if return_value == SQL_SUCCESS || return_value == SQL_SUCCESS_WITH_INFO
			push!(descriptions,nullstrip(dsn_desc))
			push!(attributes,nullstrip(dsn_attr))
		else
		break
		end
	end
	dsns = [descriptions attributes]
end