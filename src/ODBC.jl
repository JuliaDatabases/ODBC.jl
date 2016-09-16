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

using DataStreams, DataFrames, NullableArrays, CategoricalArrays, WeakRefStrings

if VERSION < v"0.5.0-dev+4267"
    if OS_NAME == :Windows
        const KERNEL = :NT
    else
        const KERNEL = OS_NAME
    end

    @eval is_apple()   = $(KERNEL == :Darwin)
    @eval is_linux()   = $(KERNEL == :Linux)
    @eval is_bsd()     = $(KERNEL in (:FreeBSD, :OpenBSD, :NetBSD, :Darwin, :Apple))
    @eval is_unix()    = $(is_linux() || is_bsd())
    @eval is_windows() = $(KERNEL == :NT)
else
    const KERNEL = Sys.KERNEL
end

if is_unix()
    using DecFP
end

if !isdefined(Core, :String)
    typealias String UTF8String
end

if !isdefined(Base, :unsafe_wrap)
    unsafe_wrap{A<:Array}(::Type{A}, ptr, len, own) = pointer_to_array(ptr, len, own)
end

if !isdefined(Base, :transcode)
    transcode(::Type{UInt8}, dat) = Base.encode_to_utf8(eltype(dat), dat, length(dat))
end

if !isdefined(Base, Symbol("@static"))
     macro static(ex)
        if isa(ex, Expr)
            if ex.head === :if
                cond = eval(current_module(), ex.args[1])
                if cond
                    return esc(ex.args[2])
                elseif length(ex.args) == 3
                    return esc(ex.args[3])
                else
                    return nothing
                end
            end
        end
        throw(ArgumentError("invalid @static macro"))
    end
end

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
    quote
        ret = $func
        ret != ODBC.API.SQL_SUCCESS && ret != ODBC.API.SQL_SUCCESS_WITH_INFO && ODBCError($handle, $handletype) &&
            throw(ODBCError("$($str) failed; return code: $ret => $(ODBC.API.RETURN_VALUES[ret])"))
        nothing
    end
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
function DSN(dsn::AbstractString, username::AbstractString=String(""), password::AbstractString=String(""); driver_prompt::Integer=ODBC.API.SQL_DRIVER_NOPROMPT)
    dbc = ODBC.ODBCAllocHandle(ODBC.API.SQL_HANDLE_DBC, ODBC.ENV)
    dsns = ODBC.listdsns()
    found = false
    for d in dsns[:,1]
        dsn == d && (found = true)
    end
    if found
        @CHECK dbc ODBC.API.SQL_HANDLE_DBC ODBC.API.SQLConnect(dbc, dsn, username, password)
    else
        dsn = ODBCDriverConnect!(dbc, dsn, driver_prompt % UInt16)
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
