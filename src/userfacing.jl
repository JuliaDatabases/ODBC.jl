#connect: Connect to DSN, returns Connection object, also stores Connection information in global default 'conn' object and global 'Connections' connections array
function connect(dsn::String,username,password)
	global Connections
	global conn
	global env
	dsn_number = 0
	if env == C_NULL env = ODBCAllocHandle(SQL_HANDLE_ENV,SQL_NULL_HANDLE) end
	dbc = ODBCAllocHandle(SQL_HANDLE_DBC,env)
	ODBCConnect(dbc,dsn,username,password)
	stmt = ODBCAllocHandle(SQL_HANDLE_STMT,dbc)
		for x in 1:length(Connections)
			if (Connections[x].dsn==dsn)
				dsn_number+=1
			end
		end
		conn = Connection(dsn,dsn_number+1,dbc,stmt,null_resultset)
		push!(Connections,conn)
		println("Connection $(conn.number) to $(conn.dsn) successful.")  
end
connect(dsn::String) = connect(dsn,"","") #Convenience method when username and password are already setup in DSN
#avancedconnect: 
function advancedconnect(conn_string::String,driver_prompt::Uint16)
	global Connections
	global conn
	global env
	dsn_number = 0
	if env == C_NULL env = ODBCAllocHandle(SQL_HANDLE_ENV,SQL_NULL_HANDLE) end
	dbc = ODBCAllocHandle(SQL_HANDLE_DBC,env)
	ODBCDriverConnect(dbc,conn_string,driver_prompt)
	stmt = ODBCAllocHandle(SQL_HANDLE_STMT,dbc)
		for x in 1:length(Connections)
			if (Connections[x].dsn==conn_string)
				dsn_number+=1
			end
		end
		conn = Connection(conn_string,dsn_number+1,dbc,stmt,null_resultset)
		push!(Connections,conn)
		println("Connection $(conn.number) to $(conn.dsn) successful.")  
end
advancedconnect() = advancedconnect(" ",SQL_DRIVER_PROMPT)
advancedconnect(conn_string::String) = advancedconnect(conn_string,SQL_DRIVER_PROMPT)
#query: Sends query string to DBMS, once executed, resultset metadata is returned, space is allocated, and results are returned
function query(conn::Connection, querystring::String, output::Union(String,Array{String,1}),delim::Union(Char,Array{Char,1})) 
	if conn == null_connection
		error("[ODBC]: A valid connection was not specified (and no valid default connection exists)")
	end
	ODBCFreeStmt(conn.stmt_ptr)
	ODBCQueryExecute(conn.stmt_ptr,querystring)
	holder = ref(DataFrame)
		while true
			meta = ODBCMetadata(conn.stmt_ptr,querystring)
			push!(holder,ODBCFetch(conn.stmt_ptr,meta,output,delim,length(holder)))
			(@FAILED SQLMoreResults(conn.stmt_ptr)) && break
		end
	conn.resultset = length(holder) == 1 ? holder[1] : holder
	ODBCFreeStmt(conn.stmt_ptr)
	return conn.resultset
end
query(querystring::String) = query(conn, querystring, "DataFrame",',') #Convenience method when using default connection 'conn'
query(conn::Connection,querystring::String) = query(conn, querystring, "DataFrame",',')
query(querystring::String,output::Union(String,Array{String,1})) = query(conn, querystring, output,',')
macro sql_str(s)
	query(s)
end
#querymeta: Sends query string to DBMS, once executed, resultset metadata is returned
function querymeta(conn::Connection, querystring::String) 
	if conn == null_connection
		error("[ODBC]: A valid connection was not specified (and no valid default connection exists)")
	end
	ODBCFreeStmt(conn.stmt_ptr)
	ODBCQueryExecute(conn.stmt_ptr,querystring)
	holder = ref(Metadata)
	while true
		push!(holder,ODBCMetadata(conn.stmt_ptr,querystring))
		(@FAILED SQLMoreResults(conn.stmt_ptr)) && break
	end
	conn.resultset = length(holder) == 1 ? holder[1] : holder
	ODBCFreeStmt(conn.stmt_ptr)
	return conn.resultset
end
querymeta(querystring::String) = querymeta(conn, querystring) #Convenience method when using default connection 'conn'
#disconnect:
function disconnect(connection::Connection)
	global conn
	global Connections
	ODBCFreeStmt(connection.stmt_ptr)
	SQLDisconnect(connection.dbc_ptr)
		for x = 1:length(Connections)
			if connection.dsn == Connections[x].dsn && connection.number == Connections[x].number
				Connections = delete!(Connections,x)
				if is(conn,connection)
					if length(Connections) != 0
						conn = Connections[end]
					else
						conn = null_connection #Create null default connection
					end
				end
			end
		end
	println("$(connection.dsn) connection number $(connection.number) disconnected successfully")
end
disconnect() = disconnect(conn)

#List Installed Drivers
function listdrivers()
	global env
	if env == C_NULL env = ODBCAllocHandle(SQL_HANDLE_ENV,SQL_NULL_HANDLE) end
	descriptions = ref(String)
	attributes = ref(String)
	driver_desc = Array(Uint8, 256)
	desc_length = Array(Int16, 1)
	driver_attr = Array(Uint8, 256)
	attr_length = Array(Int16, 1)
	while @SUCCEEDED SQLDrivers(env,driver_desc,desc_length,driver_attr,attr_length)	
		push!(descriptions,nullstrip(driver_desc))
		push!(attributes,nullstrip(driver_attr))
	end
	[descriptions attributes]
end
#List defined DSNs
function listdsns()
	global env
	if env == C_NULL env = ODBCAllocHandle(SQL_HANDLE_ENV,SQL_NULL_HANDLE) end
	descriptions = ref(String)
	attributes = ref(String)
	dsn_desc = Array(Uint8, 256)
	desc_length = Array(Int16, 1)
	dsn_attr = Array(Uint8, 256)
	attr_length = Array(Int16, 1)
	while @SUCCEEDED SQLDataSources(env,dsn_desc,desc_length,dsn_attr,attr_length)
		push!(descriptions,nullstrip(dsn_desc))
		push!(attributes,nullstrip(dsn_attr))
	end
	[descriptions attributes]
end
