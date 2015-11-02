using DataStreams
module ODBC

using Compat, NullableArrays, DataStreams, CSV, SQLite


type ODBCError <: Exception
    msg::AbstractString
end

function ODBCError(handle::Ptr{Void},handletype::Int16)
    i = Int16(1)
    state = zeros(ODBC.API.SQLWCHAR,6)
    error_msg = zeros(ODBC.API.SQLWCHAR, 1024)
    native = zeros(Int,1)
    msg_length = zeros(Int16,1)
    while ODBC.API.SQLGetDiagRec(handletype,handle,i,state,native,error_msg,msg_length) == ODBC.API.SQL_SUCCESS
        st  = ODBCClean(state,1,5)
        msg = ODBCClean(error_msg, 1, msg_length[1])
        println("[ODBC] $st: $msg")
        i = Int16(i+1)
    end
    return true
end

#Macros to to check if a function returned a success value or not
macro CHECK(handle,handletype,func)
    str = string(func)
    quote
        ret = $func
        ret != ODBC.API.SQL_SUCCESS && ret != ODBC.API.SQL_SUCCESS_WITH_INFO && ODBCError($handle,$handletype) &&
            throw(ODBCError("$($str) failed; return code: $ret => $(ODBC.API.RETURN_VALUES[ret])"))
        nothing
    end
end

include("API.jl")
include("utils.jl")

# List Installed Drivers
function listdrivers()
    descriptions = AbstractString[]
    attributes   = AbstractString[]
    driver_desc = zeros(ODBC.API.SQLWCHAR, 256)
    desc_length = zeros(Int16, 1)
    driver_attr = zeros(ODBC.API.SQLWCHAR, 256)
    attr_length = zeros(Int16, 1)
    while ODBC.API.SQLDrivers(ENV, driver_desc, desc_length, driver_attr, attr_length) == ODBC.API.SQL_SUCCESS
        push!(descriptions, ODBCClean(driver_desc, 1, desc_length[1]))
        push!(attributes,   ODBCClean(driver_attr, 1, attr_length[1]))
    end
    return [descriptions attributes]
end

# List defined DSNs
function listdsns()
    descriptions = AbstractString[]
    attributes   = AbstractString[]
    dsn_desc    = zeros(ODBC.API.SQLWCHAR, 256)
    desc_length = zeros(Int16, 1)
    dsn_attr    = zeros(ODBC.API.SQLWCHAR, 256)
    attr_length = zeros(Int16, 1)
    while ODBC.API.SQLDataSources(ENV, dsn_desc, desc_length, dsn_attr, attr_length) == ODBC.API.SQL_SUCCESS
        push!(descriptions, ODBCClean(dsn_desc, 1, desc_length[1]))
        push!(attributes,   ODBCClean(dsn_attr, 1, attr_length[1]))
    end
    return [descriptions attributes]
end

"DSN represents an established ODBC connection"
type DSN
    dsn::AbstractString
    dbc_ptr::Ptr{Void}
    stmt_ptr::Ptr{Void}
end

Base.show(io::IO,conn::DSN) = print(io,"ODBC.DSN($(conn.dsn))")

# Connect to DSN, returns DSN object,
function DSN(dsn::AbstractString, username::AbstractString="", password::AbstractString="";driver_prompt::Integer=ODBC.API.SQL_DRIVER_NOPROMPT)
    dbc = ODBCAllocHandle(ODBC.API.SQL_HANDLE_DBC, ODBC.ENV)
    dsns = ODBC.listdsns()
    found = false
    for d in dsns[:,1]
        dsn == d && (found = true)
    end
    if found
        @CHECK dbc ODBC.API.SQL_HANDLE_DBC ODBC.API.SQLConnect(dbc,dsn,username,password)
    else
        dsn = ODBCDriverConnect!(dbc, dsn, driver_prompt % UInt16)
    end
    stmt = ODBCAllocHandle(ODBC.API.SQL_HANDLE_STMT, dbc)
    conn = DSN(dsn, dbc, stmt)
    return conn
end

function disconnect!(conn::DSN)
    ODBCFreeStmt!(conn.stmt_ptr)
    SQLDisconnect(conn.dbc_ptr)
    return nothing
end

immutable ResultBlock
    columns::Vector{Block}
    indcols::Vector{Vector{ODBC.API.SQLLEN}}
    fetchsize::Int
end

type Source <: Data.Source
    schema::Data.Schema
    dsn::DSN
    query::AbstractString
    rb::ResultBlock
    status::Int
    rowsfetched::Ref{ODBC.API.SQLLEN}
end

include("backend.jl")
include("userfacing.jl")

function __init__()
    global const ENV = ODBCAllocHandle(ODBC.API.SQL_HANDLE_ENV, ODBC.API.SQL_NULL_HANDLE)
end

end #ODBC module
