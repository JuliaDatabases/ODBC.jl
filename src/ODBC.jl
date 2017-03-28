module ODBC

using DataStreams, DataFrames, NullableArrays, CategoricalArrays, WeakRefStrings

export Data, DataFrame

include("API.jl")

"just a block of memory; T is the element type, `len` is total # of **bytes** pointed to, and `elsize` is size of each element"
type Block{T}
    ptr::Ptr{T}    # pointer to a block of memory
    len::Int       # total # of bytes in block
    elsize::Int    # size between elements in bytes
end

"""
Block allocator:
    -Takes an element type, and number of elements to allocate in a linear block
    -Optionally specify an extra dimension of elements that make up each element (i.e. container types)
"""
function Block{T}(::Type{T}, elements::Int, extradim::Integer=1)
    len = sizeof(T) * elements * extradim
    block = Block{T}(convert(Ptr{T}, Libc.malloc(len)), len, sizeof(T) * extradim)
    finalizer(block, x->Libc.free(x.ptr))
    return block
end

# used for getting messages back from ODBC driver manager; SQLDrivers, SQLError, etc.
Base.string(block::Block, len::Integer) = String(transcode(UInt8, unsafe_wrap(Array, block.ptr, len, false)))

type ODBCError <: Exception
    msg::String
end

const BUFLEN = 1024

function ODBCError(handle::Ptr{Void}, handletype::Int16)
    i = Int16(1)
    state = ODBC.Block(ODBC.API.SQLWCHAR, 6)
    native = Ref{ODBC.API.SQLINTEGER}()
    error_msg = ODBC.Block(ODBC.API.SQLWCHAR, BUFLEN)
    msg_length = Ref{ODBC.API.SQLSMALLINT}()
    while ODBC.API.SQLGetDiagRec(handletype, handle, i, state.ptr, native, error_msg.ptr, BUFLEN, msg_length) == ODBC.API.SQL_SUCCESS
        st  = string(state, 5)
        msg = string(error_msg, msg_length[])
        println("[ODBC] $st: $msg")
        i += 1
    end
    return true
end

#Macros to to check if a function returned a success value or not
macro CHECK(handle, handletype, func)
    str = string(func)
    esc(quote
        ret = $func
        ret != ODBC.API.SQL_SUCCESS && ret != ODBC.API.SQL_SUCCESS_WITH_INFO && ODBCError($handle, $handletype) &&
            throw(ODBCError("$($str) failed; return code: $ret => $(ODBC.API.RETURN_VALUES[ret])"))
        nothing
    end)
end

"List ODBC drivers that have been installed and registered"
function listdrivers()
    descriptions = String[]
    attributes   = String[]
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

"List ODBC DSNs, both user and system, that have been previously defined"
function listdsns()
    descriptions = String[]
    attributes   = String[]
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

"""
A DSN represents an established ODBC connection.
It is passed to most other ODBC methods as a first argument
"""
type DSN
    dsn::String
    dbc_ptr::Ptr{Void}
    stmt_ptr::Ptr{Void}
    stmt_ptr2::Ptr{Void}
end

Base.show(io::IO,conn::DSN) = print(io, "ODBC.DSN($(conn.dsn))")

"""
Construct a `DSN` type by connecting to a valid ODBC DSN or by specifying a valid connection string.
Takes optional 2nd and 3rd arguments for `username` and `password`, respectively.
1st argument `dsn` can be either the name of a pre-defined ODBC DSN or a valid connection string.
A great resource for building valid connection strings is [http://www.connectionstrings.com/](http://www.connectionstrings.com/).
"""
function DSN(dsn::AbstractString, username::AbstractString=String(""), password::AbstractString=String(""); prompt::Bool=true)
    dbc = ODBC.ODBCAllocHandle(ODBC.API.SQL_HANDLE_DBC, ODBC.ENV)
    dsns = ODBC.listdsns()
    found = false
    for d in dsns[:,1]
        dsn == d && (found = true)
    end
    if found
        @CHECK dbc ODBC.API.SQL_HANDLE_DBC ODBC.API.SQLConnect(dbc, dsn, username, password)
    else
        dsn = ODBCDriverConnect!(dbc, dsn, prompt)
    end
    stmt = ODBCAllocHandle(ODBC.API.SQL_HANDLE_STMT, dbc)
    stmt2 = ODBCAllocHandle(ODBC.API.SQL_HANDLE_STMT, dbc)
    conn = DSN(dsn, dbc, stmt, stmt2)
    return conn
end

"disconnect a connected `DSN`"
function disconnect!(conn::DSN)
    ODBCFreeStmt!(conn.stmt_ptr)
    ODBCFreeStmt!(conn.stmt_ptr2)
    ODBC.API.SQLDisconnect(conn.dbc_ptr)
    return nothing
end

type Statement
    dsn::DSN
    stmt::Ptr{Void}
    query::String
    task::Task
end

"An `ODBC.Source` type executes a `query` string upon construction and prepares data for streaming to an appropriate `Data.Sink`"
type Source <: Data.Source
    schema::Data.Schema
    dsn::DSN
    query::String
    columns::Vector{Any}
    status::Int
    rowsfetched::Ref{ODBC.API.SQLLEN}
    rowoffset::Int
    boundcols::Vector{Any}
    indcols::Vector{Vector{ODBC.API.SQLLEN}}
    sizes::Vector{ODBC.API.SQLULEN}
    ctypes::Vector{ODBC.API.SQLSMALLINT}
    jltypes::Vector{DataType}
end

Base.show(io::IO, source::Source) = print(io, "ODBC.Source:\n\tDSN: $(source.dsn)\n\tstatus: $(source.status)\n\tschema: $(source.schema)")

include("Source.jl")
include("Sink.jl")

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
