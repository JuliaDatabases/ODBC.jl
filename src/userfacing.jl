# Connect to DSN, returns Connection object,
function connect(dsn::AbstractString; usr::AbstractString="", pwd::AbstractString="")
    dbc = ODBCAllocHandle(SQL_HANDLE_DBC, ENV)
    ODBCConnect!(dbc, dsn, usr, pwd)
    stmt = ODBCAllocHandle(SQL_HANDLE_STMT, dbc)
    conn = Connection(dsn, dbc, stmt, 0)
    return conn
end

function advancedconnect(conn_string::AbstractString="", driver_prompt::Uint16=SQL_DRIVER_NOPROMPT)
    dbc = ODBCAllocHandle(SQL_HANDLE_DBC, ENV)
    out_conn = ODBCDriverConnect!(dbc, conn_string, driver_prompt)
    stmt = ODBCAllocHandle(SQL_HANDLE_STMT, dbc)
    conn = Connection(out_conn, dbc, stmt, 0)
    return conn
end

# query: Sends query string to DBMS,
# once executed, space is allocated and
# results and resultset metadata are returned
function query(conn::Connection, querystring::AbstractString; meta::Bool=false, output::AbstractString="")
    ODBC.ODBCFreeStmt!(conn.stmt_ptr)
    ODBC.ODBCQueryExecute(conn.stmt_ptr, querystring)
    holder = []
    while true
        metadata = ODBC.ODBCMetadata(conn.stmt_ptr, querystring)
        if meta
            push!(holder,metadata)
        else
            if metadata.rows == 0
                push!(holder, [])
            else
                columns, indicator, rowset = ODBCBindCols(conn.stmt_ptr, metadata)
                resultset = output == "" ? (metadata.rows > 0 ? ODBCFetch(conn.stmt_ptr, metadata,columns, rowset, indicator) :
                                                                ODBCFetchPush(conn.stmt_ptr, metadata,columns, rowset,indicator)) :
                                           ODBCFetchToFile(conn.stmt_ptr, metadata, columns, rowset, output, length(holder))
                push!(holder,resultset)
            end
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
macro sql_str(s)
    query(s)
end

# Replaces backticks in the query string with escaped quotes
# for convenience in using "" in column names, etc.
macro query(x)
    :(query(replace($x, '`', '\"')))
end

function disconnect!(conn::Connection)
    ODBCFreeStmt!(conn.stmt_ptr)
    SQLDisconnect(conn.dbc_ptr)
    return nothing
end

# List Installed Drivers
function listdrivers()
    descriptions = AbstractString[]
    attributes   = AbstractString[]
    driver_desc = zeros(SQLWCHAR, 256)
    desc_length = zeros(Int16, 1)
    driver_attr = zeros(SQLWCHAR, 256)
    attr_length = zeros(Int16, 1)
    while @SUCCEEDED SQLDrivers(ENV, driver_desc, desc_length, driver_attr, attr_length)
        push!(descriptions, ODBCClean(driver_desc, 1, desc_length[1]))
        push!(attributes,   ODBCClean(driver_attr, 1, attr_length[1]))
    end
    return [descriptions attributes]
end

# List defined DSNs
function listdsns()
    descriptions = AbstractString[]
    attributes   = AbstractString[]
    dsn_desc    = zeros(SQLWCHAR, 256)
    desc_length = zeros(Int16, 1)
    dsn_attr    = zeros(SQLWCHAR, 256)
    attr_length = zeros(Int16, 1)
    while @SUCCEEDED SQLDataSources(ENV, dsn_desc, desc_length, dsn_attr, attr_length)
        push!(descriptions, ODBCClean(dsn_desc, 1, desc_length[1]))
        push!(attributes,   ODBCClean(dsn_attr, 1, attr_length[1]))
    end
    return [descriptions attributes]
end
