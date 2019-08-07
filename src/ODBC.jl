module ODBC

using Tables, CategoricalArrays, WeakRefStrings, DataFrames, Dates, DecFP

export DataFrame, odbcdf

include("API.jl")

"just a block of memory; T is the element type, `len` is total # of **bytes** pointed to, and `elsize` is size of each element"
mutable struct Block{T}
    ptr::Ptr{T}    # pointer to a block of memory
    len::Int       # total # of bytes in block
    elsize::Int    # size between elements in bytes
end

"""
Block allocator:
    -Takes an element type, and number of elements to allocate in a linear block
    -Optionally specify an extra dimension of elements that make up each element (i.e. container types)
"""
function Block(::Type{T}, elements::Int, extradim::Integer=1) where {T}
    len = sizeof(T) * elements * extradim
    block = Block{T}(convert(Ptr{T}, Libc.malloc(len)), len, sizeof(T) * extradim)
    finalizer(x->Libc.free(x.ptr), block)
    return block
end

# used for getting messages back from ODBC driver manager; SQLDrivers, SQLError, etc.
Base.string(block::Block, len::Integer) = String(transcode(UInt8, unsafe_wrap(Array, block.ptr, len, own=false)))

struct ODBCError <: Exception
    msg::String
end

const BUFLEN = 1024

function ODBCError(handle::Ptr{Cvoid}, handletype::Int16)
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

# Macros to to check if a function returned a success value or not
macro CHECK(handle, handletype, func)
    str = string(func)
    esc(quote
        ret = $func
        ret != ODBC.API.SQL_SUCCESS && ret != ODBC.API.SQL_SUCCESS_WITH_INFO && ret != API.SQL_NO_DATA && ODBCError($handle, $handletype) &&
            throw(ODBCError("$($str) failed; return code: $ret => $(ODBC.API.RETURN_VALUES[ret])"))
        ret
    end)
end

"List ODBC drivers that have been installed and registered"
function drivers()
    descriptions = String[]
    attributes   = String[]
    driver_desc = Block(ODBC.API.SQLWCHAR, BUFLEN)
    desc_length = Ref{ODBC.API.SQLSMALLINT}()
    driver_attr = Block(ODBC.API.SQLWCHAR, BUFLEN)
    attr_length = Ref{ODBC.API.SQLSMALLINT}()
    dir = ODBC.API.SQL_FETCH_FIRST
    while ODBC.API.SQLDrivers(ENV[], dir, driver_desc.ptr, BUFLEN, desc_length, driver_attr.ptr, BUFLEN, attr_length) == ODBC.API.SQL_SUCCESS
        push!(descriptions, string(driver_desc, desc_length[]))
        push!(attributes,   string(driver_attr, attr_length[]))
        dir = ODBC.API.SQL_FETCH_NEXT
    end
    return [descriptions attributes]
end

"List ODBC DSNs, both user and system, that have been previously defined"
function dsns()
    descriptions = String[]
    attributes   = String[]
    dsn_desc    = Block(ODBC.API.SQLWCHAR, BUFLEN)
    desc_length = Ref{ODBC.API.SQLSMALLINT}()
    dsn_attr    = Block(ODBC.API.SQLWCHAR, BUFLEN)
    attr_length = Ref{ODBC.API.SQLSMALLINT}()
    dir = ODBC.API.SQL_FETCH_FIRST
    while ODBC.API.SQLDataSources(ENV[], dir, dsn_desc.ptr, BUFLEN, desc_length, dsn_attr.ptr, BUFLEN, attr_length) == ODBC.API.SQL_SUCCESS
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
mutable struct DSN
    dsn::String
    dbc_ptr::Ptr{Cvoid}
    stmt_ptr::Ptr{Cvoid}
    stmt_ptr2::Ptr{Cvoid}
end

Base.show(io::IO,conn::DSN) = print(io, "ODBC.DSN($(conn.dsn))")

const dsn = DSN("", C_NULL, C_NULL, C_NULL)

"""
Construct a `DSN` type by connecting to a valid ODBC DSN or by specifying a valid connection string.
Takes optional 2nd and 3rd arguments for `username` and `password`, respectively.
1st argument `dsn` can be either the name of a pre-defined ODBC DSN or a valid connection string.
A great resource for building valid connection strings is [http://www.connectionstrings.com/](http://www.connectionstrings.com/).
"""
function DSN(connectionstring::AbstractString, username::AbstractString=String(""), password::AbstractString=String(""); prompt::Bool=true)
    dbc = ODBC.ODBCAllocHandle(ODBC.API.SQL_HANDLE_DBC, ODBC.ENV[])
    dsns = ODBC.dsns()
    found = false
    for d in dsns[:,1]
        connectionstring == d && (found = true)
    end
    if found
        @CHECK dbc ODBC.API.SQL_HANDLE_DBC ODBC.API.SQLConnect(dbc, connectionstring, username, password)
    else
        connectionstring = ODBCDriverConnect!(dbc, connectionstring, prompt)
    end
    stmt = ODBCAllocHandle(ODBC.API.SQL_HANDLE_STMT, dbc)
    stmt2 = ODBCAllocHandle(ODBC.API.SQL_HANDLE_STMT, dbc)
    global dsn
    dsn.dsn = connectionstring
    dsn.dbc_ptr = dbc
    dsn.stmt_ptr = stmt
    dsn.stmt_ptr2 = stmt2
    return DSN(connectionstring, dbc, stmt, stmt2)
end

"disconnect a connected `DSN`"
function disconnect!(conn::DSN)
    ODBCFreeStmt!(conn.stmt_ptr)
    ODBCFreeStmt!(conn.stmt_ptr2)
    ODBC.API.SQLDisconnect(conn.dbc_ptr)
    return nothing
end

mutable struct Statement
    dsn::DSN
    stmt::Ptr{Cvoid}
    query::String
    task::Task
end

# used to 'clear' a statement of bound columns, resultsets,
# and other bound parameters in preparation for a subsequent query
function ODBCFreeStmt!(stmt)
    ODBC.API.SQLFreeStmt(stmt, ODBC.API.SQL_CLOSE)
    ODBC.API.SQLFreeStmt(stmt, ODBC.API.SQL_UNBIND)
    ODBC.API.SQLFreeStmt(stmt, ODBC.API.SQL_RESET_PARAMS)
end

# "Allocate ODBC handles for interacting with the ODBC Driver Manager"
function ODBCAllocHandle(handletype, parenthandle)
    handle = Ref{Ptr{Cvoid}}()
    API.SQLAllocHandle(handletype, parenthandle, handle)
    handle = handle[]
    if handletype == API.SQL_HANDLE_ENV
        API.SQLSetEnvAttr(handle, API.SQL_ATTR_ODBC_VERSION, API.SQL_OV_ODBC3)
    end
    return handle
end

# "Alternative connect function that allows user to create datasources on the fly through opening the ODBC admin"
function ODBCDriverConnect!(dbc::Ptr{Cvoid}, conn_string, prompt::Bool)
    @static if Sys.iswindows()
        driver_prompt = prompt ? API.SQL_DRIVER_PROMPT : API.SQL_DRIVER_NOPROMPT
        window_handle = prompt ? ccall((:GetForegroundWindow, :user32), Ptr{Cvoid}, () ) : C_NULL
    else
        driver_prompt = API.SQL_DRIVER_NOPROMPT
        window_handle = C_NULL
    end
    out_conn = Block(API.SQLWCHAR, BUFLEN)
    out_buff = Ref{Int16}()
    @CHECK dbc API.SQL_HANDLE_DBC API.SQLDriverConnect(dbc, window_handle, conn_string, out_conn.ptr, BUFLEN, out_buff, driver_prompt)
    connection_string = string(out_conn, out_buff[])
    return connection_string
end

"`prepare` prepares an SQL statement to be executed"
function prepare(dsn::DSN, query::AbstractString)
    stmt = ODBCAllocHandle(API.SQL_HANDLE_STMT, dsn.dbc_ptr)
    @CHECK stmt API.SQL_HANDLE_STMT API.SQLPrepare(stmt, query)
    return Statement(dsn, stmt, query, Task(1))
end

function execute!(statement::Statement, values)
    stmt = statement.stmt
    values2 = Any[cast(x) for x in values]
    strlens = zeros(API.SQLLEN, length(values2))
    for (i, v) in enumerate(values2)
        if ismissing(v)
            strlens[i] = API.SQL_NULL_DATA
            @CHECK stmt API.SQL_HANDLE_STMT API.SQLBindParameter(stmt, i, API.SQL_PARAM_INPUT,
                API.SQL_C_CHAR, API.SQL_CHAR, 0, 0, C_NULL, 0, pointer(strlens, i))
        else
            T = typeof(v)
            ctype, sqltype = API.julia2C[T], API.julia2SQL[T]
            csize, len, dgts = sqllength(v), clength(v), digits(v)
            strlens[i] = len
            ptr = getpointer(T, values2, i)
            # println("ctype: $ctype, sqltype: $sqltype, digits: $dgts, len: $len, csize: $csize")
            @CHECK stmt API.SQL_HANDLE_STMT API.SQLBindParameter(stmt, i, API.SQL_PARAM_INPUT,
                ctype, sqltype, csize, dgts, ptr, len, pointer(strlens, i))
        end
    end
    GC.@preserve values2 strlens execute!(statement)
    return
end

function execute!(statement::Statement)
    stmt = statement.stmt
    @CHECK stmt API.SQL_HANDLE_STMT API.SQLExecute(stmt)
    return
end

"`execute!` is a minimal method for just executing an SQL `query` string. No results are checked for or returned."
function execute!(dsn::DSN, query::AbstractString, stmt=dsn.stmt_ptr)
    ODBCFreeStmt!(stmt)
    @CHECK stmt API.SQL_HANDLE_STMT API.SQLExecDirect(stmt, query)
    return
end

include("Sink.jl")
include("Query.jl")
# include("sqlreplmode.jl")

const ENV = Ref{Ptr{Cvoid}}()

function __init__()
    ENV[] = ODBC.ODBCAllocHandle(ODBC.API.SQL_HANDLE_ENV, ODBC.API.SQL_NULL_HANDLE)
end

end #ODBC module
