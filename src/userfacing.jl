


# query: Sends query string to DBMS,
# once executed, space is allocated and
# results and resultset metadata are returned
function query{T}(conn::DSN, querystring::AbstractString, ::Type{T}=Matrix{Any}; justmeta::Bool=false)
    ODBC.ODBCFreeStmt!(conn.stmt_ptr)
    ODBC.ODBCQueryExecute(conn.stmt_ptr, querystring)
    holder = []
    while true
        meta = ODBC.ODBCMetadata(conn.stmt_ptr, querystring)
        if justmeta
            push!(holder, meta)
        else
            if meta.rows == 0
                push!(holder, [])
            else
                columns, indicator, rowset = ODBCBindCols(conn.stmt_ptr, meta)
                resultset = output == "" ? (meta.rows > 0 ? ODBCFetch(conn.stmt_ptr, meta, columns, rowset, indicator) :
                                                                ODBCFetchPush(conn.stmt_ptr, meta,columns, rowset, indicator)) :
                                           ODBCFetchToFile(conn.stmt_ptr, meta, columns, rowset, output, length(holder))
                push!(holder, resultset)
            end
        end
        (SQLMoreResults(conn.stmt_ptr) != SQL_SUCCESS) && break
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
