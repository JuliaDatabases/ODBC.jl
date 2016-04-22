using DataStreams
module ODBC

using Compat, NullableArrays, DataStreams, CSV, SQLite

include("API.jl")
include("utils.jl")

type ODBCError <: Exception
    msg::AbstractString
end

const BUFLEN = 1024

function ODBCError(handle::Ptr{Void},handletype::Int16)
    i = Int16(1)
    state = ODBC.Block(ODBC.API.SQLWCHAR,6)
    native = Ref{ODBC.API.SQLINTEGER}()
    error_msg = ODBC.Block(ODBC.API.SQLWCHAR, BUFLEN)
    msg_length = Ref{ODBC.API.SQLSMALLINT}()
    while ODBC.API.SQLGetDiagRec(handletype,handle,i,state.ptr,native,error_msg.ptr,BUFLEN,msg_length) == ODBC.API.SQL_SUCCESS
        st  = string(state,5)
        msg = string(error_msg, msg_length[])
        println("[ODBC] $st: $msg")
        i += 1
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

# List Installed Drivers
function listdrivers()
    descriptions = AbstractString[]
    attributes   = AbstractString[]
    driver_desc = Block(ODBC.API.SQLWCHAR, BUFLEN)
    desc_length = Ref{ODBC.API.SQLSMALLINT}()
    driver_attr = Block(ODBC.API.SQLWCHAR, BUFLEN)
    attr_length = Ref{ODBC.API.SQLSMALLINT}()
    dir = ODBC.API.SQL_FETCH_FIRST
    while ODBC.API.SQLDrivers(ENV, dir, driver_desc.ptr, BUFLEN, desc_length, driver_attr.ptr, BUFLEN, attr_length) == ODBC.API.SQL_SUCCESS
        push!(descriptions, string(driver_desc, desc_length[]))
        push!(attributes,   string(driver_attr, attr_length[]))
        dir = ODBC.API.SQL_FETCH_NEXT
    end
    return [descriptions attributes]
end

# List defined DSNs
function listdsns()
    descriptions = AbstractString[]
    attributes   = AbstractString[]
    dsn_desc    = Block(ODBC.API.SQLWCHAR, BUFLEN)
    desc_length = Ref{ODBC.API.SQLSMALLINT}()
    dsn_attr    = Block(ODBC.API.SQLWCHAR, BUFLEN)
    attr_length = Ref{ODBC.API.SQLSMALLINT}()
    dir = ODBC.API.SQL_FETCH_FIRST
    while ODBC.API.SQLDataSources(ENV, dir, dsn_desc.ptr, BUFLEN, desc_length, dsn_attr.ptr, BUFLEN, attr_length) == ODBC.API.SQL_SUCCESS
        push!(descriptions, string(dsn_desc, desc_length[]))
        push!(attributes,   string(dsn_attr, attr_length[]))
        dir = ODBC.API.SQL_FETCH_NEXT
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
    dbc = ODBC.ODBCAllocHandle(ODBC.API.SQL_HANDLE_DBC, ODBC.ENV)
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
    ODBC.API.SQLDisconnect(conn.dbc_ptr)
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
    global const ENV = ODBC.ODBCAllocHandle(ODBC.API.SQL_HANDLE_ENV, ODBC.API.SQL_NULL_HANDLE)
end

# used to 'clear' a statement of bound columns, resultsets,
# and other bound parameters in preparation for a subsequent query
function ODBCFreeStmt!(stmt)
    ODBC.API.SQLFreeStmt(stmt,ODBC.API.SQL_CLOSE)
    ODBC.API.SQLFreeStmt(stmt,ODBC.API.SQL_UNBIND)
    ODBC.API.SQLFreeStmt(stmt,ODBC.API.SQL_RESET_PARAMS)
end

end #ODBC module
