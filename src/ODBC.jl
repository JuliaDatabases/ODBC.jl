using DataStreams
"""
library for interfacing with an ODBC Driver Manager.
Handles connecting to systems, sending queries/statements and returning results, if any.

Types include:

  * `DSN` representing a valid ODBC connection
  * `ODBC.Source` representing an executed query string ready for returning results

Methods:

  * `ODBC.listdrivers` for listing installed and registered drivers in the ODBC Driver Manager
  * `ODBC.listdsns` for listing pre-defined ODBC DSNs in the ODBC Driver Manager
  * `ODBC.query` for executing and returning the results of an SQL query string

See the help documentation for the individual types/methods for more information.
"""
module ODBC

using Compat, NullableArrays, DataStreams, CSV, SQLite, DecFP

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
    free!(state)
    free!(error_msg)
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

"List ODBC drivers that have been installed and registered"
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
    free!(driver_desc)
    free!(driver_attr)
    return [descriptions attributes]
end

"List ODBC DSNs, both user and system, that have been previously defined"
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
    free!(dsn_desc)
    free!(dsn_attr)
    return [descriptions attributes]
end

"""
A DSN represents an established ODBC connection.
It is passed to most other ODBC methods as a first argument
"""
type DSN
    dsn::AbstractString
    dbc_ptr::Ptr{Void}
    stmt_ptr::Ptr{Void}
end

Base.show(io::IO,conn::DSN) = print(io,"ODBC.DSN($(conn.dsn))")

"""
Construct a `DSN` type by connecting to a valid ODBC DSN or by specifying a valid connection string.
Takes optional 2nd and 3rd arguments for `username` and `password`, respectively.
1st argument `dsn` can be either the name of a pre-defined ODBC DSN or a valid connection string.
A great resource for building valid connection strings is [http://www.connectionstrings.com/](http://www.connectionstrings.com/).
"""
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

"disconnect a connected `DSN`"
function disconnect!(conn::DSN)
    ODBCFreeStmt!(conn.stmt_ptr)
    ODBC.API.SQLDisconnect(conn.dbc_ptr)
    return nothing
end

"Internal transition type for use while fetching results of an SQL query from a DSN"
immutable ResultBlock
    columns::Vector{Block}
    indcols::Vector{Vector{ODBC.API.SQLLEN}}
    jltypes::Vector{DataType}
    fetchsize::Int
    rowsfetched::Ref{ODBC.API.SQLLEN}
end

Base.show(io::IO, rb::ResultBlock) = print(io, "ODBC.ResultBlock:\n\trowsfetched: $(rb.rowsfetched)\n\tfetchsize: $(rb.fetchsize)\n\tcolumns: $(length(rb.columns))\n\t$(rb.jltypes)")

"An `ODBC.Source` type executes a `query` string upon construction and prepares data for streaming to an appropriate `Data.Sink`"
type Source <: Data.Source
    schema::Data.Schema
    dsn::DSN
    query::AbstractString
    rb::ResultBlock
    status::Int
end

Base.show(io::IO, source::Source) = print(io, "ODBC.Source:\n\tDSN: $(source.dsn)\n\tstatus: $(source.status)\n\tschema: $(source.schema)")

include("backend.jl")

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
