module API

using unixODBC_jll
const unixODBC_dm = unixODBC_jll.libodbc
const unixODBC_inst = unixODBC_jll.libodbcinst

@static if Sys.iswindows()
    const odbc32_dm = "odbc32"
    const odbc32_inst = "odbccp32"
    const iODBC_dm = odbc32_dm
    const iODBC_inst = odbc32_inst
else
    using iODBC_jll
    const iODBC_dm = iODBC_jll.libiodbc
    const iODBC_inst = iODBC_jll.libiodbcinst
    const odbc32_dm = unixODBC_jll.libodbc
    const odbc32_inst = unixODBC_jll.libodbcinst
end

@enum DM_TYPE unixODBC iODBC odbc32

@static if Sys.iswindows()
    const odbc_dm = Ref(odbc32)
elseif Sys.isapple()
    const odbc_dm = Ref(iODBC)
else
    const odbc_dm = Ref(unixODBC)
end

function setunixODBC(; kw...)
    odbc_dm[] = unixODBC
    setupenv(; kw...)
    return
end

function setiODBC(; kw...)
    odbc_dm[] = iODBC
    setupenv(; kw...)
    return
end

function setodbc32(; kw...)
    odbc_dm[] = odbc32
    setupenv(; kw...)
    return
end

const SQLWCHAR = Cushort
const SQLWCHAR32 = UInt32

sqlwcharsize() = odbc_dm[] == iODBC ? SQLWCHAR32 : SQLWCHAR

include("consts.jl")
include("apitypes.jl")

str(x::Vector{UInt8}, len) = String(x[1:len])
str(x::Vector{UInt16}, len) = transcode(String, view(x, 1:len))
str(x::Vector{UInt32}, len) = transcode(String, x[1:len])
str(x::Vector{UInt32}) = unsafe_string(pointer(transcode(UInt8, x)))

function swapsqlwchar(expr)
    for i = 1:length(expr.args)
        if expr.args[i] == :(Ptr{SQLWCHAR})
            expr.args[i] = :(Ptr{SQLWCHAR32})
        end
    end
    return expr
end

macro odbc(func,args,vals...)
    esc(quote
        ret = SQL_SUCCESS
        if odbc_dm[] == iODBC
            while true
                ret = ccall( ($func, iODBC_dm), SQLRETURN, $(swapsqlwchar(args)), $(vals...))
                ret == SQL_STILL_EXECUTING || break
                sleep(0.001)
            end
        elseif odbc_dm[] == unixODBC
            while true
                ret = ccall( ($func, unixODBC_dm), SQLRETURN, $args, $(vals...))
                ret == SQL_STILL_EXECUTING || break
                sleep(0.001)
            end
        else # odbc_dm[] == odbc32
            while true
                ret = ccall( ($func, odbc32_dm), stdcall, SQLRETURN, $args, $(vals...))
                ret == SQL_STILL_EXECUTING || break
                sleep(0.001)
            end
        end
        ret
    end)
end

macro odbcinst(func,args,vals...)
    esc(quote
        if odbc_dm[] == iODBC
            ccall( ($func, iODBC_inst), SQLRETURN, $(swapsqlwchar(args)), $(vals...))
        elseif odbc_dm[] == unixODBC
            ccall( ($func, unixODBC_inst), SQLRETURN, $args, $(vals...))
        else # odbc_dm[] == odbc32
            ccall( ($func, odbc32_inst), stdcall, SQLRETURN, $args, $(vals...))
        end
    end)
end

macro checksuccess(h, expr)
    esc(quote
        ret = $expr
        if ret == SQL_SUCCESS_WITH_INFO
            @info diagnostics($h)
        elseif ret == SQL_ERROR || ret == SQL_INVALID_HANDLE
            error(diagnostics($h))
        end
        ret
    end)
end

const SQL_HANDLE_ENV  = Int16(1)
const SQL_HANDLE_DBC  = Int16(2)
const SQL_HANDLE_STMT = Int16(3)
const SQL_HANDLE_DESC = Int16(4)
const SQL_NULL_HANDLE = C_NULL

function SQLAllocHandle(handletype::SQLSMALLINT, parenthandle::Ptr{Cvoid}, handle::Ref{Ptr{Cvoid}})
    @odbc(:SQLAllocHandle,
        (SQLSMALLINT, Ptr{Cvoid}, Ref{Ptr{Cvoid}}),
        handletype, parenthandle, handle)
end

function SQLFreeHandle(handletype::SQLSMALLINT,handle::Ptr{Cvoid})
    @odbc(:SQLFreeHandle,
        (SQLSMALLINT, Ptr{Cvoid}),
        handletype, handle)
end

const SQL_ATTR_ODBC_VERSION = 200
const SQL_OV_ODBC3 = 3

function SQLSetEnvAttr(env_handle::Ptr{Cvoid}, attribute, value)
    @odbc(:SQLSetEnvAttr,
        (Ptr{Cvoid}, SQLINTEGER, UInt, SQLINTEGER),
        env_handle, attribute, value, 0)
end

mutable struct Handle
    type::Int16
    ptr::Ptr{Cvoid}
    function Handle(type, parent=SQL_NULL_HANDLE)
        ref = Ref{Ptr{Cvoid}}()
        @checksuccess parent SQLAllocHandle(type, parent isa Handle ? parent.ptr : parent, ref)
        ptr = ref[]
        ptr == C_NULL && error("error creating ODBC.API.Handle; null pointer encountered")
        if type == SQL_HANDLE_ENV
            @checksuccess parent SQLSetEnvAttr(ptr, SQL_ATTR_ODBC_VERSION, SQL_OV_ODBC3)
        end
        h = new(type, ptr)
        finalizer(h) do x
            if x.ptr != C_NULL
                SQLFreeHandle(x.type, x.ptr)
                x.ptr = C_NULL
            end
        end
        return h
    end
end

gettype(h::Handle) = h.type
getptr(h::Handle) = h.ptr == C_NULL ? error("invalid odbc handle") : h.ptr
getptr(x::Ptr) = x

const ODBC_ENV = Ref{Handle}()

const ODBCINI = abspath(joinpath(@__DIR__, "../config/odbc.ini"))
const ODBCINSTINI = abspath(joinpath(@__DIR__, "../config/odbcinst.ini"))

@assert isfile(ODBCINI) || error("error finding ODBC/config/odbc.ini file; please Pkg.build(\"ODBC\") again")
@assert isfile(ODBCINSTINI) || error("error finding ODBC/config/odbcinst.ini file; please Pkg.build(\"ODBC\") again")

function setupenv(; trace::Bool=false, tracefile::String="", kw...)
    if isdefined(ODBC_ENV, :x)
        finalize(ODBC_ENV[])
    end
    delete!(ENV, "ODBCINI")
    delete!(ENV, "ODBCSYSINI")
    delete!(ENV, "ODBCINSTINI")
    ENV["ODBCINI"] = ODBCINI
    if odbc_dm[] == iODBC
        ENV["ODBCINSTINI"] = ODBCINSTINI
    elseif odbc_dm[] == unixODBC
        ENV["ODBCSYSINI"] = realpath(joinpath(@__DIR__, "../config"))
    end
    for (k, v) in pairs(kw)
        ENV[k] = v
    end
    ODBC_ENV[] = Handle(SQL_HANDLE_ENV)
    return
end

const ODBC_DBC = Ref{Ptr{Cvoid}}()

function setdebug(trace, tracefile)
    if !isdefined(ODBC_DBC, :x) || ODBC_DBC[] == C_NULL
        SQLAllocHandle(SQL_HANDLE_DBC, getptr(ODBC_ENV[]), ODBC_DBC)
    end
    if trace
        SQLSetConnectAttr(ODBC_DBC[], SQL_ATTR_TRACE, SQL_OPT_TRACE_OFF)
        if tracefile != ""
            SQLSetConnectAttr(ODBC_DBC[], SQL_ATTR_TRACEFILE, tracefile)
        end
        SQLSetConnectAttr(ODBC_DBC[], SQL_ATTR_TRACE, SQL_OPT_TRACE_ON)
    else
        SQLSetConnectAttr(ODBC_DBC[], SQL_ATTR_TRACE, SQL_OPT_TRACE_OFF)
    end
end

function __init__()
    setupenv()
    return
end

const SQL_COMMIT = 0
const SQL_ROLLBACK = 1

function SQLEndTran(dbc, type)
    @odbc(:SQLEndTran,
        (SQLSMALLINT, Ptr{Cvoid}, SQLSMALLINT),
        SQL_HANDLE_DBC, getptr(dbc), type)
end

endtran(dbc, commit::Bool) = @checksuccess dbc SQLEndTran(dbc, commit ? SQL_COMMIT : SQL_ROLLBACK)

const SQL_ATTR_TRACE = SQLINTEGER(104)
const SQL_ATTR_TRACEFILE = SQLINTEGER(105)
const SQL_OPT_TRACE_OFF = SQLUINTEGER(0)
const SQL_OPT_TRACE_ON = SQLUINTEGER(1)

const SQL_ATTR_AUTOCOMMIT = SQLINTEGER(102)
const SQL_AUTOCOMMIT_OFF = SQLUINTEGER(0)
const SQL_AUTOCOMMIT_ON = SQLUINTEGER(1)

function SQLSetConnectAttr(dbc, attr::SQLINTEGER, value::SQLUINTEGER)
    @odbc(:SQLSetConnectAttr,
        (Ptr{Cvoid}, SQLINTEGER, SQLUINTEGER, SQLINTEGER),
        getptr(dbc), attr, value, SQL_IS_UINTEGER)
end

setcommitmode(dbc, on::Bool) = @checksuccess dbc SQLSetConnectAttr(dbc, SQL_ATTR_AUTOCOMMIT, on ? SQL_AUTOCOMMIT_ON : SQL_AUTOCOMMIT_OFF)

function SQLSetConnectAttr(dbc, attr::SQLINTEGER, value::String)
    @odbc(:SQLSetConnectAttr,
        (Ptr{Cvoid}, SQLINTEGER, Ptr{UInt8}, SQLINTEGER),
        getptr(dbc), attr, value, sizeof(value))
end

const SQL_ATTR_CONNECTION_DEAD = 1209
const SQL_CD_TRUE = 1
const SQL_CD_FALSE = 0

function SQLGetConnectAttr(dbc, attr, ret)
    ref = Ref{SQLINTEGER}()
    @odbc(:SQLGetConnectAttr,
        (Ptr{Cvoid}, SQLINTEGER, Ref{SQLUINTEGER}, SQLINTEGER, Ref{SQLINTEGER}),
        getptr(dbc), attr, ret, 0, ref)
end

function getconnectattr(dbc, attr)
    ret = Ref{SQLUINTEGER}()
    SQLGetConnectAttr(dbc, attr, ret)
    return ret[]
end

const SQL_BATCH_SUPPORT = 121
const SQL_BS_SELECT_EXPLICIT = 0x00000001
const SQL_BS_ROW_COUNT_EXPLICIT = 0x00000002
const SQL_BS_SELECT_PROC = 0x00000004
const SQL_BS_ROW_COUNT_PROC = 0x00000008

const SQL_FORWARD_ONLY_CURSOR_ATTRIBUTES2 = 147
const SQL_CA2_CRC_EXACT = 0x00001000
const SQL_CA2_CRC_APPROXIMATE = 0x00002000

function getinfosqluinteger(dbc::Handle, type=121)
    ref = Ref{SQLUINTEGER}()
    len = Ref{SQLSMALLINT}()
    @checksuccess dbc @odbc(:SQLGetInfo,
        (Ptr{Cvoid}, SQLUSMALLINT, Ref{SQLUINTEGER}, SQLSMALLINT, Ref{SQLSMALLINT}),
        getptr(dbc), type, ref, 0, len)
    return ref[]
end

const SQL_IDENTIFIER_QUOTE_CHAR = 29

function getinfostring(dbc::Handle, type)
    buf = Vector{UInt8}(undef, 6)
    len = Ref{SQLSMALLINT}()
    @checksuccess dbc @odbc(:SQLGetInfo,
        (Ptr{Cvoid}, SQLUSMALLINT, Ptr{UInt8}, SQLSMALLINT, Ref{SQLSMALLINT}),
        getptr(dbc), type, buf, sizeof(buf), len)
    return str(buf, len[])
end

const SQL_ALL_TYPES = 0

function SQLGetTypeInfo(stmt)
    @odbc(:SQLGetTypeInfo,
        (Ptr{Cvoid}, SQLSMALLINT),
        getptr(stmt), SQL_ALL_TYPES)
end

function gettypes(dbc)
    stmt = Handle(SQL_HANDLE_STMT, getptr(dbc))
    SQLGetTypeInfo(stmt)
    return stmt
end

const SQL_DRIVER_COMPLETE = UInt16(1)
const SQL_DRIVER_COMPLETE_REQUIRED = UInt16(3)
const SQL_DRIVER_NOPROMPT = UInt16(0)
const SQL_DRIVER_PROMPT = UInt16(2)

function SQLDriverConnect(dbc::Ptr{Cvoid},connstr)
    # need to call SQLDriverConnectW to ensure our application gets labelled "unicode"
    # and subsequent library calls behave properly
    c = transcode(sqlwcharsize(), connstr)
    push!(c, sqlwcharsize()(0))
    ret = @odbc(:SQLDriverConnectW,
        (Ptr{Cvoid},Ptr{Cvoid},Ptr{SQLWCHAR},SQLSMALLINT,Ptr{SQLCHAR},SQLSMALLINT,Ptr{SQLSMALLINT},SQLUSMALLINT),
        dbc,C_NULL,c,SQL_NTS,C_NULL,0,C_NULL,SQL_DRIVER_NOPROMPT)
    if ret == SQL_ERROR
        ret = @odbc(:SQLDriverConnect,
            (Ptr{Cvoid},Ptr{Cvoid},Ptr{SQLCHAR},SQLSMALLINT,Ptr{SQLCHAR},SQLSMALLINT,Ptr{SQLSMALLINT},SQLUSMALLINT),
            dbc,C_NULL,connstr,SQL_NTS,C_NULL,0,C_NULL,SQL_DRIVER_NOPROMPT)
    end
    return ret
end

function driverconnect(connstr)
    dbc = Handle(SQL_HANDLE_DBC, ODBC_ENV[])
    @checksuccess dbc SQLDriverConnect(getptr(dbc), connstr)
    return dbc
end

connect(dsn, user, pwd) = driverconnect(string("DSN=", dsn, user === nothing ? "" : ";UID=$user", pwd === nothing ? "" : ";PWD=$pwd"))

function SQLDisconnect(dbc::Ptr{Cvoid})
    @odbc(:SQLDisconnect,
        (Ptr{Cvoid},),
        dbc)
end

function disconnect(h::Handle)
    if h.type == SQL_HANDLE_DBC
        @checksuccess(h, SQLDisconnect(h.ptr))
        finalize(h)
    end
end

function cwstring(s::AbstractString)
    bytes = codeunits(String(s))
    0 in bytes && throw(ArgumentError("embedded NULs are not allowed in input strings: $(repr(s))"))
    return transcode(sqlwcharsize(), bytes)
end

function SQLPrepare(stmt::Ptr{Cvoid},query::AbstractString)
    q = cwstring(query)
    @odbc(:SQLPrepareW,
        (Ptr{Cvoid},Ptr{SQLWCHAR},Int16),
        stmt,q,length(q))
end

function prepare(dbc::Handle, sql)
    stmt = Handle(SQL_HANDLE_STMT, getptr(dbc))
    enableasync(stmt)
    @checksuccess stmt SQLPrepare(getptr(stmt), sql)
    return stmt
end

function SQLNumParams(stmt::Ptr{Cvoid},param_count::Ref{SQLSMALLINT})
    @odbc(:SQLNumParams,
        (Ptr{Cvoid},Ptr{SQLSMALLINT}),
        stmt,param_count)
end

function numparams(stmt::Handle)
    out = Ref{SQLSMALLINT}()
    @checksuccess stmt SQLNumParams(getptr(stmt), out)
    return out[]
end

const SQL_PARAM_INPUT = Int16(1)
const SQL_PARAM_OUTPUT = Int16(4)
const SQL_PARAM_INPUT_OUTPUT = Int16(2)

function SQLBindParameter(stmt,x::Int,iotype::Int16,ctype::Int16,sqltype::Int16,column_size::Int,decimal_digits::Int,param_value,param_size::Int,len::Ptr{SQLLEN})
    @odbc(:SQLBindParameter,
        (Ptr{Cvoid},UInt16,Int16,Int16,Int16,UInt,Int16,Ptr{Cvoid},Int,Ptr{SQLLEN}),
        getptr(stmt),x,iotype,ctype,sqltype,column_size,decimal_digits,param_value,param_size,len)
end

bindparam(stmt,x,iotype,ctype,sqltype,column_size,decimal_digits,param_value,param_size,len) =
    @checksuccess stmt SQLBindParameter(stmt,x,iotype,ctype,sqltype,column_size,decimal_digits,param_value,param_size,len)

const SQL_CLOSE = UInt16(0)

function SQLFreeStmt(stmt::Ptr{Cvoid},param::UInt16)
    @odbc(:SQLFreeStmt,
        (Ptr{Cvoid},UInt16),
        stmt, param)
end

function freestmt(stmt)
    if stmt.ptr != C_NULL
        SQLFreeStmt(getptr(stmt), SQL_CLOSE)
    end
end

function SQLExecute(stmt::Ptr{Cvoid})
    @odbc(:SQLExecute,
        (Ptr{Cvoid},),
        stmt)
end

execute(stmt::Handle) = @checksuccess stmt SQLExecute(getptr(stmt))

function SQLExecDirect(stmt::Ptr{Cvoid},query::AbstractString)
    q = cwstring(query)
    @odbc(:SQLExecDirectW,
        (Ptr{Cvoid},Ptr{SQLWCHAR},Int),
        stmt,q,length(q))
end

function execdirect(stmt::Handle, sql)
    @checksuccess stmt SQLExecDirect(getptr(stmt), sql)
    return stmt
end

function SQLNumResultCols(stmt::Ptr{Cvoid},cols::Ref{Int16})
    @odbc(:SQLNumResultCols,
        (Ptr{Cvoid},Ref{Int16}),
        stmt, cols)
end

function numcols(stmt::Handle)
    out = Ref{SQLSMALLINT}()
    @checksuccess stmt SQLNumResultCols(getptr(stmt), out)
    return out[]
end

function SQLRowCount(stmt::Ptr{Cvoid},rows::Ref{SQLLEN})
    @odbc(:SQLRowCount,
        (Ptr{Cvoid},Ref{SQLLEN}),
        stmt, rows)
end

function numrows(stmt::Handle)
    out = Ref{SQLLEN}()
    @checksuccess stmt SQLRowCount(getptr(stmt), out)
    return out[]
end

function SQLDescribeCol(stmt,i,nm::Vector,len::Vector,dt::Vector,cs::Vector,dd::Vector,nul::Vector)
    @odbc(:SQLDescribeColW,
        (Ptr{Cvoid},SQLUSMALLINT,Ptr{SQLWCHAR},SQLSMALLINT,Ptr{SQLSMALLINT},Ptr{SQLSMALLINT},Ptr{SQLULEN},Ptr{SQLSMALLINT},Ptr{SQLSMALLINT}),
        stmt,i,nm,length(nm),pointer(len, i),pointer(dt, i),pointer(cs, i),pointer(dd, i),pointer(nul, i))
end

const SQL_ATTR_ROW_ARRAY_SIZE = 27
const SQL_IS_UINTEGER = -5
const SQL_IS_INTEGER = -6

const SQL_ATTR_ASYNC_ENABLE = 4
const SQL_ASYNC_ENABLE_ON = 1

function SQLSetStmtAttr(stmt::Ptr{Cvoid},attribute,value,value_length)
    @odbc(:SQLSetStmtAttrW,
        (Ptr{Cvoid},SQLINTEGER,SQLULEN,SQLINTEGER),
        stmt,attribute,value,value_length)
end

setrowset(stmt::Handle, rowset) = @checksuccess stmt SQLSetStmtAttr(getptr(stmt), SQL_ATTR_ROW_ARRAY_SIZE, rowset, SQL_IS_UINTEGER)
enableasync(stmt::Handle) = SQLSetStmtAttr(getptr(stmt), SQL_ATTR_ASYNC_ENABLE, SQL_ASYNC_ENABLE_ON, SQL_IS_UINTEGER)

const SQL_ATTR_ROWS_FETCHED_PTR  = 26

function SQLSetStmtAttr(stmt::Ptr{Cvoid},attribute,value::Ref{SQLLEN},value_length)
    @odbc(:SQLSetStmtAttrW,
        (Ptr{Cvoid},SQLINTEGER,Ref{SQLLEN},SQLINTEGER),
        stmt,attribute,value,value_length)
end

const SQL_NTS = -3

function setrowsfetched(stmt)
    rowsfetchedref = Ref{SQLLEN}(0)
    SQLSetStmtAttr(getptr(stmt), SQL_ATTR_ROWS_FETCHED_PTR, rowsfetchedref, SQL_NTS)
    return rowsfetchedref
end

const SQL_FETCH_NEXT = Int16(1)

function SQLFetchScroll(stmt::Ptr{Cvoid},fetch_orientation::Int16,fetch_offset::Int)
    @odbc(:SQLFetchScroll,
        (Ptr{Cvoid},Int16,Int),
        stmt,fetch_orientation,fetch_offset)
end

fetch(stmt::Handle) = @checksuccess stmt SQLFetchScroll(getptr(stmt), SQL_FETCH_NEXT, 0)

function SQLBindCol(stmt::Ptr{Cvoid},x,ctype,mem,jlsize,indicator::Vector{SQLLEN})
    @odbc(:SQLBindCol,
        (Ptr{Cvoid},SQLUSMALLINT,SQLSMALLINT,Ptr{Cvoid},SQLLEN,Ptr{SQLLEN}),
        stmt,x,ctype,mem,jlsize,indicator)
end

function SQLGetData(stmt::Ptr{Cvoid},i,ctype,mem,jlsize,indicator::Vector{SQLLEN})
    @odbc(:SQLGetData,
        (Ptr{Cvoid},SQLUSMALLINT,SQLSMALLINT,Ptr{Cvoid},SQLLEN,Ptr{SQLLEN}),
        stmt,i,ctype,mem,jlsize,indicator)
end

function SQLMoreResults(stmt::Ptr{Cvoid})
    @odbc(:SQLMoreResults,
        (Ptr{Cvoid},),
        stmt)
end

moreresults(stmt::Handle) = @checksuccess stmt SQLMoreResults(getptr(stmt))

function SQLGetDiagRec(handletype, handle, i, state, native, error_msg, msg_length)
    @odbc(:SQLGetDiagRec,
        (SQLSMALLINT,Ptr{Cvoid},SQLSMALLINT,Ptr{SQLCHAR},Ref{SQLINTEGER},Ptr{SQLCHAR},SQLSMALLINT,Ref{SQLSMALLINT}),
        handletype,handle,i,state,native,error_msg,length(error_msg),msg_length)
end

function diagnostics(h::Handle)
    state = Vector{UInt8}(undef, 6)
    native = Ref{SQLINTEGER}()
    error = Vector{UInt8}(undef, 1024)
    len = Ref{SQLSMALLINT}()
    i = 1
    io = IOBuffer()
    while SQLGetDiagRec(gettype(h), getptr(h), i, state, native, error, len) == SQL_SUCCESS
        write(io, "$(str(state, 5)): $(str(error, len[]))")
        i += 1
    end
    return String(take!(io))
end

macro checkinst(expr)
    esc(quote
        ret = $expr
        if ret == 0
            error(installererror())
        end
        ret
    end)
end

function installererror()
    buf = Vector{UInt8}(undef, 512)
    code = Ref{UInt16}()
    len = Ref{UInt16}()
    i = 1
    err = ""
    while @odbcinst(:SQLInstallerError,
        (UInt16, Ref{UInt16}, Ptr{UInt8}, UInt16, Ref{UInt16}),
        i, code, buf, sizeof(buf), len) != SQL_NO_DATA
        err *= str(buf, len[])
        i += 1
    end
    return err
end

function getdrivers()
    name = Vector{UInt8}(undef, 1024)
    desc = Vector{UInt8}(undef, 1024)
    namelen = Ref{SQLSMALLINT}()
    desclen = Ref{SQLSMALLINT}()
    drivers = Dict{String, String}()
    while @checksuccess(ODBC_ENV[], @odbc(:SQLDrivers,
        (Ptr{Cvoid}, SQLUSMALLINT, Ptr{SQLCHAR}, SQLSMALLINT, Ref{SQLSMALLINT}, Ptr{SQLCHAR}, SQLSMALLINT, Ref{SQLSMALLINT}),
        getptr(ODBC_ENV[]), SQL_FETCH_NEXT, name, sizeof(name), namelen, desc, sizeof(desc), desclen)) == SQL_SUCCESS
        drivers[str(name, namelen[])] = str(desc, desclen[])
    end
    return drivers
end

function adddriver(name, path; kw...)
    ex = length(kw) > 0 ? "\0" * join((string(k, "=", v) for (k, v) in kw), '\0') : ""
    driver = "$name\0Driver=$path$ex\0\0"
    out = Vector{UInt8}(undef, 1024)
    ref = Ref{UInt16}()
    usage = Ref{UInt16}()
    ret = @checkinst @odbcinst(:SQLInstallDriverEx,
        (Ptr{UInt8}, Ptr{UInt8}, Ptr{UInt8}, UInt16, Ref{UInt16}, UInt16, Ref{UInt16}),
        driver, C_NULL, out, length(out), ref, 2, usage)
    return ret
end

function removedriver(name, removedsns)
    usage = Ref{UInt16}()
    ret = @checkinst @odbcinst(:SQLRemoveDriver,
        (Ptr{UInt8}, Bool, Ref{UInt16}),
        name, removedsns, usage)
    return ret
end

function getdsns()
    name = Vector{UInt8}(undef, 1024)
    desc = Vector{UInt8}(undef, 1024)
    namelen = Ref{SQLSMALLINT}()
    desclen = Ref{SQLSMALLINT}()
    dsns = Dict{String, String}()
    while @checksuccess(ODBC_ENV[], @odbc(:SQLDataSources,
        (Ptr{Cvoid}, SQLUSMALLINT, Ptr{SQLCHAR}, SQLSMALLINT, Ref{SQLSMALLINT}, Ptr{SQLCHAR}, SQLSMALLINT, Ref{SQLSMALLINT}),
        getptr(ODBC_ENV[]), SQL_FETCH_NEXT, name, sizeof(name), namelen, desc, sizeof(desc), desclen)) == SQL_SUCCESS
        dsns[str(name, namelen[])] = str(desc, desclen[])
    end
    return dsns
end

function writeinientry(file, section, key, value)
    @checkinst @odbcinst(:SQLWritePrivateProfileString,
        (Ptr{UInt8}, Ptr{UInt8}, Ptr{UInt8}, Ptr{UInt8}),
        section, string(key), string(value), file)
end

function adddsn(name, driver; kw...)
    ret = @checkinst @odbcinst(:SQLWriteDSNToIni,
        (Ptr{UInt8}, Ptr{UInt8}),
        name, driver)
    for (k, v) in kw
        writeinientry("odbc.ini", name, k, v)
    end
    return
end

function removedsn(name)
    ret = @checkinst @odbcinst(:SQLRemoveDSNFromIni,
        (Ptr{UInt8},),
        name)
    return
end

end # module API
