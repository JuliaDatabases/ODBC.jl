"""
ODBC API Function Definitions
By Jacob Quinn, 2016
In general, the ODBC functions are implemented to mirror the C header files (sql.h,sqlext.h,sqltypes.h,sqlucode.h)
A few liberties are taken in utliizing standard Julia functions and idioms
Format:
  * function name
  * URL reference
  * short function description
  * valid const definitions
  * relevant notes
  * working and tested status
  * function definition code

Contents
 * Macros and Utility Functions
 * Handle Functions
 * Connection Functions
 * Resultset Metadata Functions
 * Query Functions
 * Resultset Retrieval Functions
 * DBMS Meta Functions
 * Error Handling and Diagnostics
"""
module API

using WeakRefStrings, Dates

include("types.jl")

#### Macros and Utility Functions ####

"""
# MAXFETCHSIZE sets the default rowset fetch size
# used in retrieving resultset blocks from queries
"""
const MAXFETCHSIZE = 65535

# success codes
const SQL_SUCCESS           = Int16(0)
const SQL_SUCCESS_WITH_INFO = Int16(1)

# error codes
const SQL_ERROR             = Int16(-1)
const SQL_INVALID_HANDLE    = Int16(-2)

# status codes
const SQL_STILL_EXECUTING   = Int16(2)
const SQL_NO_DATA           = Int16(100)

const RETURN_VALUES = Dict(SQL_ERROR   => "SQL_ERROR",
                           SQL_NO_DATA => "SQL_NO_DATA",
                           SQL_INVALID_HANDLE  => "SQL_INVALID_HANDLE",
                           SQL_STILL_EXECUTING => "SQL_STILL_EXECUTING")

macro odbc(func,args,vals...)
    if Sys.iswindows()
        esc(:(ccall( ($func, $odbc_dm), stdcall, SQLRETURN, $args, $(vals...))))
    else
        esc(:(ccall( ($func, $odbc_dm),          SQLRETURN, $args, $(vals...))))
    end
end

"http://msdn.microsoft.com/en-us/library/windows/desktop/ms712400(v=vs.85).aspx"
function SQLDrivers(env::Ptr{Cvoid},
                    dir,
                    driver_desc::Ptr{SQLWCHAR},
                    desclen,
                    desc_length::Ref{SQLSMALLINT},
                    driver_attr::Ptr{SQLWCHAR},
                    attrlen,
                    attr_length::Ref{SQLSMALLINT})
    @odbc(:SQLDriversW,
                (Ptr{Cvoid}, SQLUSMALLINT, Ptr{SQLWCHAR}, SQLSMALLINT, Ref{SQLSMALLINT}, Ptr{SQLWCHAR}, SQLSMALLINT, Ref{SQLSMALLINT}),
                env, dir, driver_desc, desclen, desc_length, driver_attr, attrlen, attr_length)
end

"http://msdn.microsoft.com/en-us/library/windows/desktop/ms711004(v=vs.85).aspx"
function SQLDataSources(env::Ptr{Cvoid},
                        dir,
                        dsn_desc::Ptr{SQLWCHAR},
                        desclen,
                        desc_length::Ref{SQLSMALLINT},
                        dsn_attr::Ptr{SQLWCHAR},
                        attrlen,
                        attr_length::Ref{SQLSMALLINT})
    @odbc(:SQLDataSourcesW,
                (Ptr{Cvoid}, SQLUSMALLINT, Ptr{SQLWCHAR}, SQLSMALLINT, Ref{SQLSMALLINT}, Ptr{SQLWCHAR}, SQLSMALLINT, Ref{SQLSMALLINT}),
                env, dir, dsn_desc, desclen, desc_length, dsn_attr, attrlen, attr_length)
end

#### Handle Functions ####

# SQLAllocHandle
#"http://msdn.microsoft.com/en-us/library/windows/desktop/ms712455(v=vs.85).aspx"
# Description: allocates an environment, connection, statement, or descriptor handle
# Valid handle types
const SQL_HANDLE_ENV  = Int16(1)
const SQL_HANDLE_DBC  = Int16(2)
const SQL_HANDLE_STMT = Int16(3)
const SQL_HANDLE_DESC = Int16(4)
const SQL_NULL_HANDLE = C_NULL

#Status: Tested on Windows, Linux, Mac 32/64-bit
function SQLAllocHandle(handletype::SQLSMALLINT, parenthandle::Ptr{Cvoid}, handle::Ref{Ptr{Cvoid}})
    @odbc(:SQLAllocHandle,
                (SQLSMALLINT, Ptr{Cvoid}, Ref{Ptr{Cvoid}}),
                handletype, parenthandle, handle)
end

# SQLFreeHandle
#"http://msdn.microsoft.com/en-us/library/windows/desktop/ms710123(v=vs.85).aspx"
# Description: frees resources associated with a specific environment, connection, statement, or descriptor handle
# See SQLAllocHandle for valid handle types
# Status: Tested on Windows, Linux, Mac 32/64-bit
function SQLFreeHandle(handletype::SQLSMALLINT,handle::Ptr{Cvoid})
    @odbc(:SQLFreeHandle,
                (SQLSMALLINT, Ptr{Cvoid}),
                handletype, handle)
end

# SQLSetEnvAttr
#"http://msdn.microsoft.com/en-us/library/windows/desktop/ms709285(v=vs.85).aspx"
# Description: sets attributes that govern aspects of environments
# Valid attributes; valid values for attribute are indented
const SQL_ATTR_CONNECTION_POOLING = 201
const SQL_CP_OFF = UInt(0)
const SQL_CP_ONE_PER_DRIVER = UInt(1)
const SQL_CP_ONE_PER_HENV = UInt(2)
const SQL_CP_DEFAULT = SQL_CP_OFF
const SQL_ATTR_CP_MATCH = 202
const SQL_CP_RELAXED_MATCH = UInt(1)
const SQL_CP_STRICT_MATCH = UInt(0)
const SQL_ATTR_ODBC_VERSION = 200
const SQL_OV_ODBC2 = 2
const SQL_OV_ODBC3 = 3
const SQL_ATTR_OUTPUT_NTS = 10001
const SQL_TRUE = 1
const SQL_FALSE = 0

#Status: Tested on Windows, Linux, Mac 32/64-bit
function SQLSetEnvAttr(env_handle::Ptr{Cvoid}, attribute::Int, value::Integer)
    @odbc(:SQLSetEnvAttr,
                (Ptr{Cvoid}, Int, UInt, Int), env_handle, attribute, value, 0)
end

# SQLGetEnvAttr
#"http://msdn.microsoft.com/en-us/library/windows/desktop/ms709276(v=vs.85).aspx"
# Description: returns the current setting of an environment attribute
# Valid attributes: See SQLSetEnvAttr
# Status:
function SQLGetEnvAttr(env::Ptr{Cvoid},attribute::Int,value::Array{Int,1},bytes_returned::Array{Int,1})
    @odbc(:SQLGetEnvAttr,
                (Ptr{Cvoid}, Int, Ptr{Int}, Int, Ptr{Int}),
                env, attribute, value, 0, bytes_returned)
end

# SQLSetConnectAttr
#"http://msdn.microsoft.com/en-us/library/windows/desktop/ms713605(v=vs.85).aspx"
# Description: sets attributes that govern aspects of connections.
# Valid attributes
const SQL_ATTR_ACCESS_MODE = 101
const SQL_MODE_READ_ONLY = UInt(1)
const SQL_MODE_READ_WRITE = UInt(0)
#const SQL_ATTR_ASYNC_DBC_EVENT
#pointer
#const SQL_ATTR_ASYNC_DBC_FUNCTIONS_ENABLE
#const SQL_ASYNC_DBC_ENABLE_ON = UInt()
#const SQL_ASYNC_DBC_ENABLE_OFF = UInt()
#const SQL_ATTR_ASYNC_DBC_PCALLBACK
#pointer
#const SQL_ATTR_ASYNC_DBC_PCONTEXT
#pointer
const SQL_ATTR_ASYNC_ENABLE = 4
const SQL_ASYNC_ENABLE_OFF = UInt(0)
const SQL_ASYNC_ENABLE_ON = UInt(1)
const SQL_ATTR_AUTOCOMMIT = 102
const SQL_AUTOCOMMIT_OFF = UInt(0)
const SQL_AUTOCOMMIT_ON = UInt(1)
const SQL_ATTR_CONNECTION_TIMEOUT = 113
#uint of how long you want the connection timeout
const SQL_ATTR_CURRENT_CATALOG = 109
#string/Ptr{UInt8} of default database to use
#const SQL_ATTR_DBC_INFO_TOKEN
#pointer
const SQL_ATTR_ENLIST_IN_DTC = 1207
#pointer: Pass a DTC OLE transaction object that specifies the transaction to export to
# SQL Server, or SQL_DTC_DONE to end the connection's DTC association.
const SQL_ATTR_LOGIN_TIMEOUT = 103
#uint of how long you want the login timeout
const SQL_ATTR_METADATA_ID = 10014
#SQL_TRUE, SQL_FALSE
const SQL_ATTR_ODBC_CURSORS = 110
const SQL_CUR_USE_IF_NEEDED = UInt(0)
const SQL_CUR_USE_ODBC = UInt(1)
const SQL_CUR_USE_DRIVER = UInt(2)
const SQL_ATTR_PACKET_SIZE = 112
#uint for network packet size
const SQL_ATTR_QUIET_MODE = 111
#window handle pointer
const SQL_ATTR_TRACE = 104
const SQL_OPT_TRACE_OFF = UInt(0)
const SQL_OPT_TRACE_ON = UInt(1)
const SQL_ATTR_TRACEFILE = 105
#A null-terminated character string containing the name of the trace file.
const SQL_ATTR_TRANSLATE_LIB = 106
# A null-terminated character string containing the name of a library containing the functions SQLDriverToDataSource and
# SQLDataSourceToDriver that the driver accesses to perform tasks such as character set translation.
const SQL_ATTR_TRANSLATE_OPTION = 107
#A 32-bit flag value that is passed to the translation DLL.
const SQL_ATTR_TXN_ISOLATION = 108
#A 32-bit bitmask that sets the transaction isolation level for the current connection.

#Valid value_length
const SQL_IS_POINTER = -4
const SQL_IS_INTEGER = -6
const SQL_IS_UINTEGER = -5
const SQL_NTS = -3

#length of string or binary stream
#Status:
function SQLSetConnectAttr(dbc::Ptr{Cvoid},attribute::Int,value::UInt,value_length::Int)
    @odbc(:SQLSetConnectAttrW,
                (Ptr{Cvoid},Int,UInt,Int),
                dbc,attribute,value,value_length)
end

function SQLSetConnectAttr(dbc::Ptr{Cvoid},attribute::Int,value::Array{Int},value_length::Int)
    @odbc(:SQLSetConnectAttrW,
                (Ptr{Cvoid},Int,Ptr{Int},Int),
                dbc,attribute,value,value_length)
end

#SQLGetConnectAttr
#Description: returns the current setting of a connection attribute.
#Valid attributes: see SQLSetConnectAttr in addition to those below
const SQL_ATTR_AUTO_IPD = 10001
#SQL_TRUE, SQL_FALSE
const SQL_ATTR_CONNECTION_DEAD = 1209
const SQL_CD_TRUE = 1
const SQL_CD_FALSE = 0
#Status:
"http://msdn.microsoft.com/en-us/library/windows/desktop/ms710297(v=vs.85).aspx"
function SQLGetConnectAttr(dbc::Ptr{Cvoid},attribute::Int,value::Array{T,N},bytes_returned::Array{Int,1}) where {T,N}
    @odbc(:SQLGetConnectAttrW,
                (Ptr{Cvoid},Int,Ptr{Cvoid},Int,Ptr{Int}),
                dbc,attribute,value,sizeof(T)*N,bytes_returned)
end

#SQLSetStmtAttr
#Description: sets attributes related to a statement.
#Valid attributes
const SQL_ATTR_ROW_STATUS_PTR = 25
const SQL_ATTR_ROWS_FETCHED_PTR  = 26
const SQL_ATTR_ROW_ARRAY_SIZE = 27
const SQL_ATTR_CURSOR_TYPE = 6
const SQL_ATTR_CURSOR_SCROLLABLE = -1
const SQL_NONSCROLLABLE = 0
const SQL_SCROLLABLE = 1
const SQL_CURSOR_DYNAMIC = UInt(2)
const SQL_CURSOR_STATIC = UInt(3)
#this sets the rowset size for ExtendedFetch and FetchScroll
#Valid value_length: See SQLSetConnectAttr; SQL_IS_POINTER, SQL_IS_INTEGER, SQL_IS_UINTEGER, SQL_NTS
#Status:
"http://msdn.microsoft.com/en-us/library/windows/desktop/ms712631(v=vs.85).aspx"
function SQLSetStmtAttr(stmt::Ptr{Cvoid},attribute,value::Ref{SQLLEN},value_length)
    @odbc(:SQLSetStmtAttrW,
                (Ptr{Cvoid},SQLINTEGER,Ref{SQLLEN},SQLINTEGER),
                stmt,attribute,value,value_length)
end

function SQLSetStmtAttr(stmt::Ptr{Cvoid},attribute,value,value_length)
    @odbc(:SQLSetStmtAttrW,
                (Ptr{Cvoid},SQLINTEGER,SQLULEN,SQLINTEGER),
                stmt,attribute,value,value_length)
end


"http://msdn.microsoft.com/en-us/library/windows/desktop/ms715438(v=vs.85).aspx"
function SQLGetStmtAttr(stmt::Ptr{Cvoid},attribute::Int,value::Array{T,N},bytes_returned::Array{Int,1}) where {T,N}
    @odbc(:SQLGetStmtAttrW,
                (Ptr{Cvoid},Int,Ptr{Cvoid},Int,Ptr{Int}),
                stmt,attribute,value,sizeof(T)*N,bytes_returned)
end

#SQLFreeStmt
#Description: stops processing associated with a specific statement,
# closes any open cursors associated with the statement,
# discards pending results, or, optionally,
# frees all resources associated with the statement handle.
#Valid param
const SQL_CLOSE = UInt16(0)
const SQL_RESET_PARAMS = UInt16(3)
const SQL_UNBIND = UInt16(2)

#Status:
"http://msdn.microsoft.com/en-us/library/windows/desktop/ms709284(v=vs.85).aspx"
function SQLFreeStmt(stmt::Ptr{Cvoid},param::UInt16)
    @odbc(:SQLFreeStmt,
                (Ptr{Cvoid},UInt16),
                stmt, param)
end

"http://msdn.microsoft.com/en-us/library/windows/desktop/ms713560(v=vs.85).aspx"
function SQLSetDescField(desc::Ptr{Cvoid},i::Int16,field_id::Int16,value::Array{T,N}) where {T,N}
    @odbc(:SQLSetDescFieldW,
                (Ptr{Cvoid},Int16,Int16,Ptr{Cvoid},Int),
                desc,i,field_id,value,length(value))
end

"http://msdn.microsoft.com/en-us/library/windows/desktop/ms716370(v=vs.85).aspx"
function SQLGetDescField(desc::Ptr{Cvoid},i::Int16,attribute::Int16,value::Array{T,N},bytes_returned::Array{Int,1}) where {T,N}
    @odbc(:SQLGetDescFieldW,
                (Ptr{Cvoid},Int16,Int16,Ptr{Cvoid},Int,Ptr{Int}),
                desc,i,attribute,value,sizeof(T)*N,bytes_returned)
end

"http://msdn.microsoft.com/en-us/library/windows/desktop/ms710921(v=vs.85).aspx"
function SQLGetDescRec(desc::Ptr{Cvoid},i::Int16,name::Array{UInt8,1},name_length::Array{Int16,1},type_ptr::Array{Int16,1},subtype_ptr::Array{Int16,1},length_ptr::Array{Int,1},precision_ptr::Array{Int16,1},scale_ptr::Array{Int16,1},nullable_ptr::Array{Int16,1},)
    @odbc(:SQLGetDescRecW,
                (Ptr{Cvoid},Int16,Ptr{UInt8},Int16,Ptr{Int16},Ptr{Int16},Ptr{Int16},Ptr{Int},Ptr{Int16},Ptr{Int16},Ptr{Int16}),
                desc,i,name,length(name),name_length,type_ptr,subtype_ptr,length_ptr,precision_ptr,scale_ptr,nullable_ptr)
end

"http://msdn.microsoft.com/en-us/library/windows/desktop/ms715378(v=vs.85).aspx"
function SQLCopyDesc(source_desc::Ptr{Cvoid},dest_desc::Ptr{Cvoid})
    @odbc(:SQLCopyDesc,
                (Ptr{Cvoid},Ptr{Cvoid}),
                source_desc,dest_desc)
end

### Connection Functions ###
# SQLConnect
# Description: establishes connections to a driver and a data source
# Status:
"http://msdn.microsoft.com/en-us/library/windows/desktop/ms711810(v=vs.85).aspx"
function SQLConnect(dbc::Ptr{Cvoid},dsn,username,password)
    @odbc(:SQLConnectW,
                (Ptr{Cvoid},Ptr{SQLWCHAR},Int16,Ptr{SQLWCHAR},Int16,Ptr{SQLWCHAR},Int16),
                dbc,transcode(SQLWCHAR,dsn),length(transcode(SQLWCHAR,dsn)),transcode(SQLWCHAR,username),length(transcode(SQLWCHAR,username)),transcode(SQLWCHAR,password),length(transcode(SQLWCHAR,password)))
end

#SQLDriverConnect
#Description:
#Valid driver_prompt
const SQL_DRIVER_COMPLETE = UInt16(1)
const SQL_DRIVER_COMPLETE_REQUIRED = UInt16(3)
const SQL_DRIVER_NOPROMPT = UInt16(0)
const SQL_DRIVER_PROMPT = UInt16(2)
#Status:
"http://msdn.microsoft.com/en-us/library/windows/desktop/ms715433(v=vs.85).aspx"
function SQLDriverConnect(dbc::Ptr{Cvoid},window_handle::Ptr{Cvoid},conn_string,out_conn::Ptr{SQLWCHAR},out_len,out_buff::Ref{Int16},driver_prompt)
    @odbc(:SQLDriverConnectW,
                (Ptr{Cvoid},Ptr{Cvoid},Ptr{SQLWCHAR},SQLSMALLINT,Ptr{SQLWCHAR},SQLSMALLINT,Ptr{SQLSMALLINT},SQLUSMALLINT),
                dbc,window_handle,transcode(SQLWCHAR,conn_string),length(transcode(SQLWCHAR,conn_string)),out_conn,out_len,out_buff,driver_prompt)
end
#SQLBrowseConnect
 #Description: supports an iterative method of discovering and enumerating the attributes and attribute values required to connect to a data source
 #Status:
"http://msdn.microsoft.com/en-us/library/windows/desktop/ms714565(v=vs.85).aspx"
function SQLBrowseConnect(dbc::Ptr{Cvoid},instring::AbstractString,outstring::Array{SQLWCHAR,1},indicator::Array{Int16,1})
    @odbc(:SQLBrowseConnectW,
                (Ptr{Cvoid},Ptr{SQLWCHAR},Int16,Ptr{SQLWCHAR},Int16,Ptr{Int16}),
                dbc,transcode(SQLWCHAR,instring),length(transcode(SQLWCHAR,instring)),transcode(SQLWCHAR,outstring),length(transcode(SQLWCHAR,outstring)),indicator)
end
#SQLDisconnect
 #Description: closes the connection associated with a specific connection handle
 #Status:
"http://msdn.microsoft.com/en-us/library/windows/desktop/ms713946(v=vs.85).aspx"
function SQLDisconnect(dbc::Ptr{Cvoid})
    @odbc(:SQLDisconnect,
                (Ptr{Cvoid},),
                dbc)
end
#SQLGetFunctions
#Descriptions:
#Valid functionid

#supported will be SQL_TRUE or SQL_FALSE
#Status:
"http://msdn.microsoft.com/en-us/library/windows/desktop/ms709291(v=vs.85).aspx"
function SQLGetFunctions(dbc::Ptr{Cvoid},functionid::UInt16,supported::Array{UInt16,1})
    @odbc(:SQLGetFunctions,
                (Ptr{Cvoid},UInt16,Ptr{UInt16}),
                dbc,functionid,supported)
end

#SQLGetInfo
#Description:
#Status:
"http://msdn.microsoft.com/en-us/library/windows/desktop/ms711681(v=vs.85).aspx"
function SQLGetInfo(dbc::Ptr{Cvoid},attribute::Int,value::Array{T,N},bytes_returned::Array{Int,1}) where {T,N}
    @odbc(:SQLGetInfoW,
                (Ptr{Cvoid},Int,Ptr{Cvoid},Int,Ptr{Int}),
                dbc,attribute,value,sizeof(T)*N,bytes_returned)
end

#### Query Functions ####
#SQLNativeSql
#Description: returns the SQL string as modified by the driver
#Status:
"http://msdn.microsoft.com/en-us/library/windows/desktop/ms714575(v=vs.85).aspx"
function SQLNativeSql(dbc::Ptr{Cvoid},query_string::AbstractString,output_string::Array{SQLWCHAR,1},length_ind::Array{Int,1})
    @odbc(:SQLNativeSql,
                (Ptr{Cvoid},Ptr{SQLWCHAR},Int,Ptr{SQLWCHAR},Int,Ptr{Int}),
                dbc,transcode(SQLWCHAR,query_string),length(transcode(SQLWCHAR,query_string)),output_string,length(output_string),length_ind)
end

#SQLGetTypeInfo
#Description:
#valid sqltype
#const SQL_ALL_TYPES =
#Status:
"http://msdn.microsoft.com/en-us/library/windows/desktop/ms714632(v=vs.85).aspx"
function SQLGetTypeInfo(stmt::Ptr{Cvoid},sqltype::Int16)
    @odbc(:SQLGetTypeInfo,
                (Ptr{Cvoid},Int16),
                stmt,sqltype)
end

"http://msdn.microsoft.com/en-us/library/windows/desktop/ms713824(v=vs.85).aspx"
function SQLPutData(stmt::Ptr{Cvoid},data::Array{T},data_length::Int) where {T}
    @odbc(:SQLPutData,
                (Ptr{Cvoid},Ptr{Cvoid},Int),
                stmt,data,data_length)
end

"http://msdn.microsoft.com/en-us/library/windows/desktop/ms710926(v=vs.85).aspx"
function SQLPrepare(stmt::Ptr{Cvoid},query_string::AbstractString)
    @odbc(:SQLPrepareW,
                (Ptr{Cvoid},Ptr{SQLWCHAR},Int16),
                stmt,transcode(SQLWCHAR,query_string),length(transcode(SQLWCHAR,query_string)))
end

"http://msdn.microsoft.com/en-us/library/windows/desktop/ms713584(v=vs.85).aspx"
function SQLExecute(stmt::Ptr{Cvoid})
    @odbc(:SQLExecute,
                (Ptr{Cvoid},),
                stmt)
end

#SQLExecDirect
#Description: executes a preparable statement
#Status:
"http://msdn.microsoft.com/en-us/library/windows/desktop/ms713611(v=vs.85).aspx"
function SQLExecDirect(stmt::Ptr{Cvoid},query::AbstractString)
    @odbc(:SQLExecDirectW,
                (Ptr{Cvoid},Ptr{SQLWCHAR},Int),
                stmt,transcode(SQLWCHAR,query),length(transcode(SQLWCHAR,query)))
end

"http://msdn.microsoft.com/en-us/library/windows/desktop/ms714112(v=vs.85).aspx"
function SQLCancel(stmt::Ptr{Cvoid})
    @odbc(:SQLCancel,
                (Ptr{Cvoid},),
                stmt)
end

#### Resultset Metadata Functions ####
"http://msdn.microsoft.com/en-us/library/windows/desktop/ms715393(v=vs.85).aspx"
function SQLNumResultCols(stmt::Ptr{Cvoid},cols::Ref{Int16})
    @odbc(:SQLNumResultCols,
                (Ptr{Cvoid},Ref{Int16}),
                stmt, cols)
end

"http://msdn.microsoft.com/en-us/library/windows/desktop/ms711835(v=vs.85).aspx"
function SQLRowCount(stmt::Ptr{Cvoid},rows::Ref{Int})
    @odbc(:SQLRowCount,
                (Ptr{Cvoid},Ref{Int}),
                stmt, rows)
end

# "http://msdn.microsoft.com/en-us/library/windows/desktop/ms713558(v=vs.85).aspx"
# function SQLColAttribute(stmt::Ptr{Cvoid},x::Int,)
# = @odbc(:SQLColAttributeW,
#                 (Ptr{Cvoid},UInt16,UInt16,Ptr,Int16,Ptr{Int16},Ptr{Int}),
#                 stmt,x,)
# end

"http://msdn.microsoft.com/en-us/library/windows/desktop/ms716289(v=vs.85).aspx"
function SQLDescribeCol(stmt,x,nm::Ptr{SQLWCHAR},nmlen,len::Ref{Int16},dt::Ref{Int16},cs::Ref{SQLULEN},dd::Ref{Int16},nul::Ref{Int16})
    @odbc(:SQLDescribeColW,
                (Ptr{Cvoid},SQLUSMALLINT,Ptr{SQLWCHAR},SQLSMALLINT,Ref{SQLSMALLINT},Ref{SQLSMALLINT},Ref{SQLULEN},Ref{SQLSMALLINT},Ref{SQLSMALLINT}),
                stmt,x,nm,nmlen,len,dt,cs,dd,nul)
end

"http://msdn.microsoft.com/en-us/library/windows/desktop/ms710188(v=vs.85).aspx"
function SQLDescribeParam(stmt::Ptr{Cvoid},x::Int,sqltype::Array{Int16,1},column_size::Array{Int,1},decimal_digits::Array{Int16,1},nullable::Array{Int16,1})
    @odbc(:SQLDescribeParam,
                (Ptr{Cvoid},UInt16,Ptr{Int16},Ptr{Int},Ptr{Int16},Ptr{Int16}),
                stmt,x,sqltype,column_size,decimal_digits,nullable)
end

"http://msdn.microsoft.com/en-us/library/windows/desktop/ms712366(v=vs.85).aspx"
function SQLParamData(stmt::Ptr{Cvoid},ptr_buffer::Array{Ptr{Cvoid},1})
    @odbc(:SQLParamData,
                (Ptr{Cvoid},Ptr{Cvoid}),
                stmt,ptr_buffer)
end

"http://msdn.microsoft.com/en-us/library/windows/desktop/ms715409(v=vs.85).aspx"
function SQLNumParams(stmt::Ptr{Cvoid},param_count::Array{Int16,1})
    @odbc(:SQLNumParams,
                (Ptr{Cvoid},Ptr{Int16}),
                stmt,param_count)
end

#### Resultset Retrieval Functions ####
#SQLBindParameter
#Description:
#valid iotype
const SQL_PARAM_INPUT = Int16(1)
const SQL_PARAM_OUTPUT = Int16(4)
const SQL_PARAM_INPUT_OUTPUT = Int16(2)
#const SQL_PARAM_INPUT_OUTPUT_STREAM = Int16()
#const SQL_PARAM_OUTPUT_STREAM = Int16()
#Status:
"http://msdn.microsoft.com/en-us/library/windows/desktop/ms710963(v=vs.85).aspx"
function SQLBindParameter(stmt::Ptr{Cvoid},x::Int,iotype::Int16,ctype::Int16,sqltype::Int16,column_size::Int,decimal_digits::Int,param_value,param_size::Int,len::Ptr{SQLLEN})
    @odbc(:SQLBindParameter,
                (Ptr{Cvoid},UInt16,Int16,Int16,Int16,UInt,Int16,Ptr{Cvoid},Int,Ptr{SQLLEN}),
                stmt,x,iotype,ctype,sqltype,column_size,decimal_digits,param_value,param_size,len)
end
SQLSetParam = SQLBindParameter

"http://msdn.microsoft.com/en-us/library/windows/desktop/ms711010(v=vs.85).aspx"
function SQLBindCols(stmt::Ptr{Cvoid},x,ctype,mem,jlsize,indicator::Vector{SQLLEN})
    @odbc(:SQLBindCol,
                (Ptr{Cvoid},SQLUSMALLINT,SQLSMALLINT,Ptr{Cvoid},SQLLEN,Ptr{SQLLEN}),
                stmt,x,ctype,mem,jlsize,indicator)
end

"http://msdn.microsoft.com/en-us/library/windows/desktop/ms711707(v=vs.85).aspx"
function SQLSetCursorName(stmt::Ptr{Cvoid},cursor::AbstractString)
    @odbc(:SQLSetCursorNameW,
                (Ptr{Cvoid},Ptr{SQLWCHAR},Int16),
                stmt,transcode(SQLWCHAR,cursor),length(transcode(SQLWCHAR,cursor)))
end

"http://msdn.microsoft.com/en-us/library/windows/desktop/ms716209(v=vs.85).aspx"
function SQLGetCursorName(stmt::Ptr{Cvoid},cursor::Array{UInt8,1},cursor_length::Array{Int16,1})
    @odbc(:SQLGetCursorNameW,
                (Ptr{Cvoid},Ptr{SQLWCHAR},Int16,Ptr{Int16}),
                stmt,transcode(SQLWCHAR,cursor),length(transcode(SQLWCHAR,cursor)),cursor_length)
end

"http://msdn.microsoft.com/en-us/library/windows/desktop/ms715441(v=vs.85).aspx"
function SQLGetData(stmt::Ptr{Cvoid},i,ctype,mem,jlsize,indicator::Ref{SQLLEN})
    @odbc(:SQLGetData,
                (Ptr{Cvoid},SQLUSMALLINT,SQLSMALLINT,Ptr{Cvoid},SQLLEN,Ptr{SQLLEN}),
                stmt,i,ctype,mem,jlsize,indicator)
end

#SQLFetchScroll
#Description:
#valid fetch_orientation
const SQL_FETCH_NEXT = Int16(1)
const SQL_FETCH_PRIOR = Int16(4)
const SQL_FETCH_FIRST = Int16(2)
const SQL_FETCH_LAST = Int16(3)
const SQL_FETCH_ABSOLUTE = Int16(5)
const SQL_FETCH_RELATIVE = Int16(6)
const SQL_FETCH_BOOKMARK = Int16(8)
#Status:
"http://msdn.microsoft.com/en-us/library/windows/desktop/ms714682(v=vs.85).aspx"
function SQLFetchScroll(stmt::Ptr{Cvoid},fetch_orientation::Int16,fetch_offset::Int)
    @odbc(:SQLFetchScroll,
                (Ptr{Cvoid},Int16,Int),
                stmt,fetch_orientation,fetch_offset)
end

"http://msdn.microsoft.com/en-us/library/windows/desktop/ms713591(v=vs.85).aspx"
function SQLExtendedFetch(stmt::Ptr{Cvoid},fetch_orientation::UInt16,fetch_offset::Int,row_count_ptr::Array{Int,1},row_status_array::Array{Int16,1})
    @odbc(:SQLExtendedFetch,
                (Ptr{Cvoid},UInt16,Int,Ptr{Int},Ptr{Int16}),
                stmt,fetch_orientation,fetch_offset,row_count_ptr,row_status_array)
end

#SQLSetPos
#Description:
#valid operation
const SQL_POSITION = UInt16(0) #SQLSetPos
const SQL_REFRESH = UInt16(1) #SQLSetPos
const SQL_UPDATE = UInt16(2) #SQLSetPos
const SQL_DELETE = UInt16(3) #SQLSetPos
#valid lock_type
const SQL_LOCK_NO_CHANGE = UInt16(0) #SQLSetPos
const SQL_LOCK_EXCLUSIVE = UInt16(1) #SQLSetPos
const SQL_LOCK_UNLOCK = UInt16(2) #SQLSetPos
#Status
"http://msdn.microsoft.com/en-us/library/windows/desktop/ms713507(v=vs.85).aspx"
function SQLSetPos(stmt::Ptr{Cvoid},rownumber::T,operation::UInt16,lock_type::UInt16) where {T}
    @odbc(:SQLSetPos,
                (Ptr{Cvoid},UInt64,UInt16,UInt16),
                stmt,rownumber,operation,lock_type)
end #T can be Uint64 or UInt16 it seems

"http://msdn.microsoft.com/en-us/library/windows/desktop/ms714673(v=vs.85).aspx"
function SQLMoreResults(stmt::Ptr{Cvoid})
    @odbc(:SQLMoreResults,
                (Ptr{Cvoid},),
                stmt)
end

#SQLEndTran
#Description:
#valid completion_type
const SQL_COMMIT = Int16(0) #SQLEndTran
const SQL_ROLLBACK = Int16(1) #SQLEndTran
#Status:
"http://msdn.microsoft.com/en-us/library/windows/desktop/ms716544(v=vs.85).aspx"
function SQLEndTran(handletype::Int16,handle::Ptr{Cvoid},completion_type::Int16)
    @odbc(:SQLEndTran,
                (Int16,Ptr{Cvoid},Int16),
                handletype,handle,completion_type)
end

"http://msdn.microsoft.com/en-us/library/windows/desktop/ms709301(v=vs.85).aspx"
function SQLCloseCursor(stmt::Ptr{Cvoid})
    @odbc(:SQLCloseCursor,
                (Ptr{Cvoid},),
                stmt)
end

#SQLBulkOperations
#Description:
#valid operation
const SQL_ADD = UInt16(4) #SQLBulkOperations
const SQL_UPDATE_BY_BOOKMARK = UInt16(5) #SQLBulkOperations
const SQL_DELETE_BY_BOOKMARK = UInt16(6) #SQLBulkOperations
const SQL_FETCH_BY_BOOKMARK = UInt16(7) #SQLBulkOperations
#Status:
"http://msdn.microsoft.com/en-us/library/windows/desktop/ms712471(v=vs.85).aspx"
function SQLBulkOperations(stmt::Ptr{Cvoid},operation::UInt16)
    @odbc(:SQLBulkOperations,
                (Ptr{Cvoid},UInt16),
                stmt,operation)
end

#### DBMS Meta Functions ####
"http://msdn.microsoft.com/en-us/library/windows/desktop/ms711683(v=vs.85).aspx"
function SQLColumns(stmt::Ptr{Cvoid},catalog::AbstractString,schema::AbstractString,table::AbstractString,column::AbstractString)
    @odbc(:SQLColumnsW,
                (Ptr{Cvoid},Ptr{SQLWCHAR},Int16,Ptr{SQLWCHAR},Int16,Ptr{SQLWCHAR},Int16,Ptr{SQLWCHAR},Int16),
                stmt,transcode(SQLWCHAR,catalog),length(transcode(SQLWCHAR,catalog)),transcode(SQLWCHAR,schema),length(transcode(SQLWCHAR,schema)),transcode(SQLWCHAR,table),length(transcode(SQLWCHAR,table)),transcode(SQLWCHAR,column),length(transcode(SQLWCHAR,column)))
end

"http://msdn.microsoft.com/en-us/library/windows/desktop/ms716336(v=vs.85).aspx"
function SQLColumnPrivileges(stmt::Ptr{Cvoid},catalog::AbstractString,schema::AbstractString,table::AbstractString,column::AbstractString)
    @odbc(:SQLColumnPrivilegesW,
                (Ptr{Cvoid},Ptr{SQLWCHAR},Int16,Ptr{SQLWCHAR},Int16,Ptr{SQLWCHAR},Int16,Ptr{SQLWCHAR},Int16),
                stmt,transcode(SQLWCHAR,catalog),length(transcode(SQLWCHAR,catalog)),transcode(SQLWCHAR,schema),length(transcode(SQLWCHAR,schema)),transcode(SQLWCHAR,table),length(transcode(SQLWCHAR,table)),transcode(SQLWCHAR,column),length(transcode(SQLWCHAR,column)))
end

"http://msdn.microsoft.com/en-us/library/windows/desktop/ms709315(v=vs.85).aspx"
function SQLForeignKeys(stmt::Ptr{Cvoid},pkcatalog::AbstractString,pkschema::AbstractString,pktable::AbstractString,fkcatalog::AbstractString,fkschema::AbstractString,fktable::AbstractString)
    @odbc(:SQLForeignKeysW,
                (Ptr{Cvoid},Ptr{SQLWCHAR},Int16,Ptr{SQLWCHAR},Int16,Ptr{SQLWCHAR},Int16,Ptr{SQLWCHAR},Int16,Ptr{SQLWCHAR},Int16,Ptr{SQLWCHAR},Int16),
                stmt,transcode(SQLWCHAR,catalog),length(transcode(SQLWCHAR,pkcatalog)),transcode(SQLWCHAR,schema),length(transcode(SQLWCHAR,pkschema)),transcode(SQLWCHAR,table),length(transcode(SQLWCHAR,pktable)),transcode(SQLWCHAR,catalog),length(transcode(SQLWCHAR,fkcatalog)),transcode(SQLWCHAR,schema),length(transcode(SQLWCHAR,fkschema)),transcode(SQLWCHAR,table),length(transcode(SQLWCHAR,fktable)))
end

"http://msdn.microsoft.com/en-us/library/windows/desktop/ms711005(v=vs.85).aspx"
function SQLPrimaryKeys(stmt::Ptr{Cvoid},catalog::AbstractString,schema::AbstractString,table::AbstractString)
    @odbc(:SQLPrimaryKeysW,
                (Ptr{Cvoid},Ptr{SQLWCHAR},Int16,Ptr{SQLWCHAR},Int16,Ptr{SQLWCHAR},Int16),
                stmt,transcode(SQLWCHAR,catalog),length(transcode(SQLWCHAR,catalog)),transcode(SQLWCHAR,schema),length(transcode(SQLWCHAR,schema)),transcode(SQLWCHAR,table),length(transcode(SQLWCHAR,table)))
end

"http://msdn.microsoft.com/en-us/library/windows/desktop/ms711701(v=vs.85).aspx"
function SQLProcedureColumns(stmt::Ptr{Cvoid},catalog::AbstractString,schema::AbstractString,proc::AbstractString,column::AbstractString)
    @odbc(:SQLProcedureColumnsW,
                (Ptr{Cvoid},Ptr{SQLWCHAR},Int16,Ptr{SQLWCHAR},Int16,Ptr{SQLWCHAR},Int16,Ptr{SQLWCHAR},Int16),
                stmt,transcode(SQLWCHAR,catalog),length(transcode(SQLWCHAR,catalog)),transcode(SQLWCHAR,schema),length(transcode(SQLWCHAR,schema)),proc,length(proc),transcode(SQLWCHAR,column),length(transcode(SQLWCHAR,column)))
end

"http://msdn.microsoft.com/en-us/library/windows/desktop/ms715368(v=vs.85).aspx"
function SQLProcedures(stmt::Ptr{Cvoid},catalog::AbstractString,schema::AbstractString,proc::AbstractString)
    @odbc(:SQLProceduresW,
                (Ptr{Cvoid},Ptr{SQLWCHAR},Int16,Ptr{SQLWCHAR},Int16,Ptr{SQLWCHAR},Int16),
                stmt,transcode(SQLWCHAR,catalog),length(transcode(SQLWCHAR,catalog)),transcode(SQLWCHAR,schema),length(transcode(SQLWCHAR,schema)),proc,length(proc))
end

"http://msdn.microsoft.com/en-us/library/windows/desktop/ms711831(v=vs.85).aspx"
function SQLTables(stmt::Ptr{Cvoid},catalog::AbstractString,schema::AbstractString,table::AbstractString,table_type::AbstractString)
    @odbc(:SQLTablesW,
                (Ptr{Cvoid},Ptr{SQLWCHAR},Int16,Ptr{SQLWCHAR},Int16,Ptr{SQLWCHAR},Int16,Ptr{SQLWCHAR},Int16),
                stmt,transcode(SQLWCHAR,catalog),length(transcode(SQLWCHAR,catalog)),transcode(SQLWCHAR,schema),length(transcode(SQLWCHAR,schema)),transcode(SQLWCHAR,table),length(transcode(SQLWCHAR,table)),table_type,length(table_type))
end

"http://msdn.microsoft.com/en-us/library/windows/desktop/ms713565(v=vs.85).aspx"
function SQLTablePrivileges(stmt::Ptr{Cvoid},catalog::AbstractString,schema::AbstractString,table::AbstractString)
    @odbc(:SQLTablePrivilegesW,
                (Ptr{Cvoid},Ptr{SQLWCHAR},Int16,Ptr{SQLWCHAR},Int16,Ptr{SQLWCHAR},Int16),
                stmt,transcode(SQLWCHAR,catalog),length(transcode(SQLWCHAR,catalog)),transcode(SQLWCHAR,schema),length(transcode(SQLWCHAR,schema)),transcode(SQLWCHAR,table),length(transcode(SQLWCHAR,table)))
end

#SQLStatistics
#Description:
#valid unique
const SQL_INDEX_ALL = UInt16(1)
const SQL_INDEX_CLUSTERED = UInt16(1)
const SQL_INDEX_HASHED = UInt16(2)
const SQL_INDEX_OTHER = UInt16(3)
const SQL_INDEX_UNIQUE = UInt16(0)
#valid reserved
const SQL_ENSURE = UInt16(1)
const SQL_QUICK = UInt16(0)
#Status:
"http://msdn.microsoft.com/en-us/library/windows/desktop/ms711022(v=vs.85).aspx"
function SQLStatistics(stmt::Ptr{Cvoid},catalog::AbstractString,schema::AbstractString,table::AbstractString,unique::UInt16,reserved::UInt16)
    @odbc(:SQLStatisticsW,
                (Ptr{Cvoid},Ptr{UInt8},Int16,Ptr{UInt8},Int16,Ptr{UInt8},Int16,UInt16,UInt16),
                stmt,transcode(SQLWCHAR,catalog),length(transcode(SQLWCHAR,catalog)),transcode(SQLWCHAR,schema),length(transcode(SQLWCHAR,schema)),transcode(SQLWCHAR,table),length(transcode(SQLWCHAR,table)),unique,reserved)
end

#SQLSpecialColumns
#Description:
#valid id_type
const SQL_BEST_ROWID        = Int16(1) #SQLSpecialColumns
const SQL_ROWVER            = Int16(2) #SQLSpecialColumns
#valid scope
const SQL_SCOPE_CURROW      = Int16(0) #SQLSpecialColumns
const SQL_SCOPE_SESSION     = Int16(2) #SQLSpecialColumns
const SQL_SCOPE_TRANSACTION = Int16(1) #SQLSpecialColumns
#valid nullable
const SQL_NO_NULLS          = Int16(0) #SQLSpecialColumns
const SQL_NULLABLE          = Int16(1) #SQLSpecialColumns
#const SQL_NULLABLE_UNKNOWN = Int16() #SQLSpecialColumns
#Status:
"http://msdn.microsoft.com/en-us/library/windows/desktop/ms714602(v=vs.85).aspx"
function SQLSpecialColumns(stmt::Ptr{Cvoid},id_type::Int16,catalog::AbstractString,schema::AbstractString,table::AbstractString,scope::Int16,nullable::Int16)
    @odbc(:SQLSpecialColumnsW,
                (Ptr{Cvoid},Int16,Ptr{SQLWCHAR},Int16,Ptr{SQLWCHAR},Int16,Ptr{SQLWCHAR},Int16,Int16,Int16),
                stmt,id_type,transcode(SQLWCHAR,catalog),length(transcode(SQLWCHAR,catalog)),transcode(SQLWCHAR,schema),length(transcode(SQLWCHAR,schema)),transcode(SQLWCHAR,table),length(transcode(SQLWCHAR,table)),scope,nullable)
end

#### Error Handling Functions ####
#TODO: add consts
"http://msdn.microsoft.com/en-us/library/windows/desktop/ms710181(v=vs.85).aspx"
function SQLGetDiagField(handletype::Int16,handle::Ptr{Cvoid},i::Int16,diag_id::Int16,diag_info::Array{SQLWCHAR,1},buffer_length::Int16,diag_length::Array{Int16,1})
    @odbc(:SQLGetDiagFieldW,
                (Int16,Ptr{Cvoid},Int16,Int16,Ptr{SQLWCHAR},Int16,Ptr{Int16}),
                handletype,handle,i,diag_id,transcode(SQLWCHAR,diag_info),buffer_length,transcode(SQLWCHAR,msg_length))
end

"http://msdn.microsoft.com/en-us/library/windows/desktop/ms716256(v=vs.85).aspx"
function SQLGetDiagRec(handletype,handle,i,state::Ptr{SQLWCHAR},native::Ref{SQLINTEGER},error_msg,errlen,msg_length)
    @odbc(:SQLGetDiagRecW,
                (SQLSMALLINT,Ptr{Cvoid},SQLSMALLINT,Ptr{SQLWCHAR},Ref{SQLINTEGER},Ptr{SQLWCHAR},SQLSMALLINT,Ref{SQLSMALLINT}),
                handletype,handle,i,state,native,error_msg,errlen,msg_length)
end

end # module
