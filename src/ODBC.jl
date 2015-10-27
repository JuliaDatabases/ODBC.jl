using DataStreams
module ODBC

using Compat, NullableArrays, DataStreams, CSV, SQLite

type ODBCError <: Exception
    msg::AbstractString
end

include("ODBC_Types.jl")
include("ODBC_API.jl")

# List Installed Drivers
function listdrivers()
    descriptions = AbstractString[]
    attributes   = AbstractString[]
    driver_desc = zeros(SQLWCHAR, 256)
    desc_length = zeros(Int16, 1)
    driver_attr = zeros(SQLWCHAR, 256)
    attr_length = zeros(Int16, 1)
    while SQLDrivers(ENV, driver_desc, desc_length, driver_attr, attr_length) == SQL_SUCCESS
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
    while SQLDataSources(ENV, dsn_desc, desc_length, dsn_attr, attr_length) == SQL_SUCCESS
        push!(descriptions, ODBCClean(dsn_desc, 1, desc_length[1]))
        push!(attributes,   ODBCClean(dsn_attr, 1, attr_length[1]))
    end
    return [descriptions attributes]
end

"Holds metadata related to an executed query resultset"
type Metadata
    querystring::AbstractString
    cols::Int
    rows::Int
    colnames::Array{UTF8String}
    coltypes::Array{Int16}
    colsizes::Array{Int}
    coldigits::Array{Int16}
    colnulls::Array{Int16}
end

Base.show(io::IO,meta::Metadata) = begin
    println(io, "Resultset metadata for executed query")
    println(io, "-------------------------------------")
    println(io, "Query:   $(meta.querystring)")
    println(io, "Columns: $(meta.cols)")
    println(io, "Rows:    $(meta.rows)")
    println(io, [meta.colnames;
                 meta.coltypes;
                 map(x->get(SQL_TYPES, Int(x), "SQL_CHAR"),meta.coltypes);
                 map(x->get(C_TYPES, Int(x), "SQL_C_CHAR"),meta.coltypes);
                 map(x->get(SQL2Julia, Int(x), UInt8),meta.coltypes);
                 meta.colsizes;
                 meta.coldigits;
                 meta.colnulls])
end

"DSN represents an established ODBC connection"
type DSN
    dsn::AbstractString
    dbc_ptr::Ptr{Void}
    stmt_ptr::Ptr{Void}
end

Base.show(io::IO,conn::DSN) = print(io,"ODBC.DSN($(conn.dsn))")

# Connect to DSN, returns DSN object,
function DSN(dsn::AbstractString, username::AbstractString="", password::AbstractString="";driver_prompt::Integer=SQL_DRIVER_NOPROMPT)
    dbc = ODBCAllocHandle(SQL_HANDLE_DBC, ODBC.ENV)
    dsns = ODBC.listdsns()
    found = false
    for d in dsns[:,1]
        dsn == d && (found = true)
    end
    if found
        ODBCConnect!(dbc, dsn, username, password)
    else
        dsn = ODBCDriverConnect!(dbc, dsn, driver_prompt % UInt16)
    end
    stmt = ODBCAllocHandle(SQL_HANDLE_STMT, dbc)
    conn = DSN(dsn, dbc, stmt)
    return conn
end

function disconnect!(conn::DSN)
    ODBCFreeStmt!(conn.stmt_ptr)
    SQLDisconnect(conn.dbc_ptr)
    return nothing
end

type Source <: Data.Source
    schema::Data.Schema
    metadata::Metadata
    query::AbstractString
    dsn::DSN
end

include("backend.jl")
include("userfacing.jl")

function __init__()
    global const ENV = ODBC.ODBCAllocHandle(ODBC.SQL_HANDLE_ENV, ODBC.SQL_NULL_HANDLE)
end

end #ODBC module
