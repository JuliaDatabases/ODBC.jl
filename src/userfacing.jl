# Connect to DSN, returns Connection object,
# also stores Connection information in global default
# 'conn' object and global 'Connections' connections array
"""
    connect(dsn::AbstractString; usr::AbstractString="", pwd::AbstractString="")

Function to connect to a data source by specifying a data source name.
Optional parameters are user and password.
"""
function connect(dsn::AbstractString; usr::AbstractString="", pwd::AbstractString="")
    global Connections, conn, env
    env == C_NULL && (env = ODBCAllocHandle(SQL_HANDLE_ENV, SQL_NULL_HANDLE))
    dbc = ODBCAllocHandle(SQL_HANDLE_DBC, env)
    ODBCConnect!(dbc, dsn, usr, pwd)
    stmt = ODBCAllocHandle(SQL_HANDLE_STMT, dbc)
    dsn_number = 0
    for c in Connections
        if c.dsn == dsn
            dsn_number += 1
        end
    end
    conn = Connection(dsn, dsn_number+1, dbc, stmt, null_resultset)
    push!(Connections, conn)
    return conn
end

"""
    advancedconnect(conn_string::AbstractString="", driver_prompt::UInt16=SQL_DRIVER_NOPROMPT)

Native implementation of ODBC `SQLDriverConnect` function.
The input parameter is a connection string, like, `"DSN=userdsn;UID=johnjacob;PWD=jingle;"`
"""
function advancedconnect(conn_string::AbstractString="", driver_prompt::UInt16=SQL_DRIVER_NOPROMPT)
    global Connections, conn, env
    env == C_NULL && (env = ODBCAllocHandle(SQL_HANDLE_ENV, SQL_NULL_HANDLE))
    dbc = ODBCAllocHandle(SQL_HANDLE_DBC, env)
    ODBCDriverConnect!(dbc, conn_string, driver_prompt)
    stmt = ODBCAllocHandle(SQL_HANDLE_STMT, dbc)
    dsn_number = 0
    for c in Connections
        if c.dsn == conn_string
            dsn_number += 1
        end
    end
    conn = Connection(conn_string, dsn_number+1, dbc, stmt, null_resultset)
    push!(Connections, conn)
    return conn
end

"""
    query(querystring::AbstractString, conn::Connection=conn; output::Output=DataFrame, delim::Char=',')

`query` sends query string to DBMS, once executed, space is allocated and results and resultset metadata are returned.
Required parameters are the query string and connection object. Optional parameters are `Output` type and delimiter, 
by default it is `DataFrame`. Another option is to speficify a name of a file and delimiter.
"""
function query(querystring::AbstractString, conn::Connection=conn; output::Output=DataFrame, delim::Char=',')
    if conn == null_conn
        error("[ODBC]: A valid connection was not specified (and no valid default connection exists)")
    end
    ODBCFreeStmt!(conn.stmt_ptr)
    ODBCQueryExecute(conn.stmt_ptr, querystring)
    holder = DataFrame[]
    while true
        meta = ODBCMetadata(conn.stmt_ptr, querystring)
        if meta.rows == 0
            push!(holder, DataFrame())
        else
            columns, indicator, rowset = ODBCBindCols(conn.stmt_ptr, meta)
            if output == DataFrame
                if meta.rows > 0
                    resultset = ODBCFetchDataFrame(conn.stmt_ptr, meta,columns, rowset, indicator)
                else
                    resultset = ODBCFetchDataFramePush!(conn.stmt_ptr, meta,columns, rowset,indicator)
                end
            else
                resultset = ODBCDirectToFile(conn.stmt_ptr, meta,columns,
                                             rowset, output, delim, length(holder))
            end
            push!(holder,resultset)
        end
        (@FAILED SQLMoreResults(conn.stmt_ptr)) && break
    end
    conn.resultset = length(holder) == 1 ? holder[1] : holder
    ODBCFreeStmt!(conn.stmt_ptr)
    return conn.resultset
end

# sql"..." string literal for convenience;
# it doesn't do anything different than query right now,
# but we could potentially do some interesting things here
"Same are query()."
macro sql_str(s)
    query(s)
end

# Replaces backticks in the query string with escaped quotes
# for convenience in using "" in column names, etc.
macro query(x)
    :(query(replace($x, '`', '\"')))
end

# it may seem odd to include the other arguments for querymeta,
# but it's so switching between query and querymeta doesn't require exluding args (convenience)
"""
    querymeta(querystring::AbstractString,conn::Connection=conn; output::Output=DataFrame,delim::Char=',')

Sends query string to DBMS, once executed, return resultset metadata. Input parameters expected are the query string and the connection object. By default the output is returned as a `DataFrame`. Output can also be written to a file passing the name of the file as `AbstractString`, the delimiter could also be specified, which by default is comma.
"""
function querymeta(querystring::AbstractString,conn::Connection=conn; output::Output=DataFrame,delim::Char=',')
    if conn == null_conn
        error("[ODBC]: A valid connection was not specified (and no valid default connection exists)")
    end
    ODBCFreeStmt!(conn.stmt_ptr)
    ODBCQueryExecute(conn.stmt_ptr, querystring)
    holder = Metadata[]
    while true
        push!(holder,ODBCMetadata(conn.stmt_ptr, querystring))
        (@FAILED SQLMoreResults(conn.stmt_ptr)) && break
    end
    conn.resultset = length(holder) == 1 ? holder[1] : holder
    ODBCFreeStmt!(conn.stmt_ptr)
    return conn.resultset
end

"""
    disconnect(connection::Connection=conn)

`disconnect` closes a connection type, frees all handles and resets the default connection conn as necessary. If invoked with no arguments (i.e. disconnect()), the defaut connection conn is closed.
"""
function disconnect(connection::Connection=conn)
    global Connections, conn
    ODBCFreeStmt!(connection.stmt_ptr)
    SQLDisconnect(connection.dbc_ptr)
    for x = 1:length(Connections)
        if connection.dsn == Connections[x].dsn &&
           connection.number == Connections[x].number
            splice!(Connections,x)
            if conn === connection
                if length(Connections) != 0
                    conn = Connections[end]
                else
                    # reset conn to null default connection
                    conn = null_conn
                end
            end
        end
    end
end

"List all the installed database drivers."
function listdrivers()
    global env
    env == C_NULL && (env = ODBCAllocHandle(SQL_HANDLE_ENV, SQL_NULL_HANDLE))
    descriptions = AbstractString[]
    attributes   = AbstractString[]
    driver_desc = zeros(UInt8, 256)
    desc_length = zeros(Int16, 1)
    driver_attr = zeros(UInt8, 256)
    attr_length = zeros(Int16, 1)
    while @SUCCEEDED SQLDrivers(env, driver_desc, desc_length, driver_attr, attr_length)
        push!(descriptions, ODBCClean(driver_desc, 1, desc_length[1]))
        push!(attributes,   ODBCClean(driver_attr, 1, attr_length[1]))
    end
    return descriptions, attributes
end

"List all the DSNs."
function listdsns()
    global env
    env == C_NULL && (env = ODBCAllocHandle(SQL_HANDLE_ENV,SQL_NULL_HANDLE) )
    descriptions = AbstractString[]
    attributes   = AbstractString[]
    dsn_desc    = zeros(UInt8, 256)
    desc_length = zeros(Int16, 1)
    dsn_attr    = zeros(UInt8, 256)
    attr_length = zeros(Int16, 1)
    while @SUCCEEDED SQLDataSources(env, dsn_desc, desc_length, dsn_attr, attr_length)
        push!(descriptions, ODBCClean(dsn_desc, 1, desc_length[1]))
        push!(attributes,   ODBCClean(dsn_attr, 1, attr_length[1]))
    end
    return descriptions, attributes
end
