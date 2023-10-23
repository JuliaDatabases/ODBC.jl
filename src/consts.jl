# Translation of sqltypes.h; C typealiases for SQL functions
# http://msdn.microsoft.com/en-us/library/windows/desktop/ms716298(v=vs.85).aspx
# http://msdn.microsoft.com/en-us/library/windows/desktop/aa383751(v=vs.85).aspx
const SQLCHAR =       UInt8
const SQLSMALLINT =   Cshort
const SQLUSMALLINT =  Cushort

const SQLSCHAR =      Cchar
const SQLDATE =       Cuchar
const SQLDECIMAL =    Cuchar
const SQLDOUBLE =     Cdouble
const SQLFLOAT =      Cdouble

const SQLVARCHAR =    Cuchar
const SQLNUMERIC =    Cuchar
const SQLREAL =       Cfloat
const SQLTIME =       Cuchar
const SQLTIMESTAMP =  Cuchar

# ODBC API	64-bit platform	32-bit platform
# SQLINTEGER	32 bits	32 bits
# SQLUINTEGER	32 bits	32 bits
# SQLLEN	64 bits	32 bits
# SQLULEN	64 bits	32 bits
# SQLSETPOSIROW	64 bits	16 bits
# SQL_C_BOOKMARK	64 bits	32 bits
# BOOKMARK	64 bits	32 bits

const SQLINTEGER =  Cint
const SQLUINTEGER = Cuint
const SQLLEN = Int
const SQLULEN = UInt

# if WORD_SIZE == 64
#     const SQLINTEGER =    Cint
#     const SQLUINTEGER =   Cuint
# else
#     const SQLINTEGER =    Clong
#     const SQLUINTEGER =   Culong
# end
#
# const SQLLEN =        SQLINTEGER
# const SQLULEN =       SQLUINTEGER
const SQLSETPOSIROW = SQLUSMALLINT

const SQLROWCOUNT =   SQLULEN
const SQLROWSETSIZE = SQLULEN
const SQLTRANSID =    SQLULEN
const SQLROWOFFSET =  SQLLEN
const SQLPOINTER =    Ptr{Cvoid}
const SQLRETURN =     SQLSMALLINT
const SQLHANDLE =     Ptr{Cvoid}
const SQLHENV =       SQLHANDLE
const SQLHDBC =       SQLHANDLE
const SQLHSTMT =      SQLHANDLE
const SQLHDESC =      SQLHANDLE
const ULONG =         Cuint
const PULONG =        Ptr{ULONG}
const USHORT =        Cushort
const PUSHORT =       Ptr{USHORT}
const UCHAR =         Cuchar
const PUCHAR =        Ptr{Cuchar}
const PSZ =           Ptr{Cchar}
const SCHAR =         Cchar
const SDWORD =        Cint
const SWORD =         Cshort
const UDWORD =        Cuint
const UWORD =         Cushort
const SLONG =         Cint
const SSHORT =        Cshort
const SDOUBLE =       Cdouble
const LDOUBLE =       Cdouble
const SFLOAT =        Cfloat
const PTR =           Ptr{Cvoid}
const HENV =          Ptr{Cvoid}
const HDBC =          Ptr{Cvoid}
const HSTMT =         Ptr{Cvoid}
const RETCODE =       Cshort
const SQLHWND =       Ptr{Cvoid}

#################

# Data Type Mappings
# SQL data types are returned in resultset metadata calls (ODBCMetadata)
# C data types are used in SQLBindCol (ODBCFetch) to allocate column memory; the driver manager converts from the SQL type to this C type in memory
# Julia types indicate how julia should read the returned C data type memory from the previous step

# SQL Data Type                     C Data Type                         Julia Type
# ---------------------------------------------------------------------------------
# SQL_CHAR                          SQL_C_CHAR                          UInt8
# SQL_VARCHAR                       SQL_C_CHAR                          UInt8
# SQL_LONGVARCHAR                   SQL_C_CHAR                          UInt8
# SQL_WCHAR                         SQL_C_WCHAR                         Cwchar_t
# SQL_WVARCHAR                      SQL_C_WCHAR                         Cwchar_t
# SQL_WLONGVARCHAR                  SQL_C_WCHAR                         Cwchar_t
# SQL_DECIMAL                       SQL_C_DOUBLE                        SQLNumeric
# SQL_NUMERIC                       SQL_C_DOUBLE                        SQLNumeric
# SQL_SMALLINT                      SQL_C_SHORT                         Int16
# SQL_INTEGER                       SQL_C_LONG                          Int32
# SQL_REAL                          SQL_C_FLOAT                         Float64
# SQL_FLOAT                         SQL_C_DOUBLE                        Float64
# SQL_DOUBLE                        SQL_C_DOUBLE                        Float64
# SQL_BIT                           SQL_C_BIT                           Int8
# SQL_TINYINT                       SQL_C_TINYINT                       Int8
# SQL_BIGINT                        SQL_C_BIGINT                        Int64
# SQL_BINARY                        SQL_C_BINARY                        UInt8
# SQL_VARBINARY                     SQL_C_BINARY                        UInt8
# SQL_LONGVARBINARY                 SQL_C_BINARY                        UInt8
# SQL_TYPE_DATE                     SQL_C_TYPE_DATE                     SQLDate
# SQL_TYPE_TIME                     SQL_C_TYPE_TIME                     SQLTime
# SQL_TYPE_TIMESTAMP                SQL_C_TYPE_TIMESTAMP                SQLTimestamp
# SQL_INTERVAL_MONTH                SQL_C_INTERVAL_MONTH                UInt8
# SQL_INTERVAL_YEAR                 SQL_C_INTERVAL_YEAR                 UInt8
# SQL_INTERVAL_YEAR_TO_MONTH        SQL_C_INTERVAL_YEAR_TO_MONTH        UInt8
# SQL_INTERVAL_DAY                  SQL_C_INTERVAL_DAY                  UInt8
# SQL_INTERVAL_HOUR                 SQL_C_INTERVAL_HOUR                 UInt8
# SQL_INTERVAL_MINUTE               SQL_C_INTERVAL_MINUTE               UInt8
# SQL_INTERVAL_SECOND               SQL_C_INTERVAL_SECOND               UInt8
# SQL_INTERVAL_DAY_TO_HOUR          SQL_C_INTERVAL_DAY_TO_HOUR          UInt8
# SQL_INTERVAL_DAY_TO_MINUTE        SQL_C_INTERVAL_DAY_TO_MINUTE        UInt8
# SQL_INTERVAL_DAY_TO_SECOND        SQL_C_INTERVAL_DAY_TO_SECOND        UInt8
# SQL_INTERVAL_HOUR_TO_MINUTE       SQL_C_INTERVAL_HOUR_TO_MINUTE       UInt8
# SQL_INTERVAL_HOUR_TO_SECOND       SQL_C_INTERVAL_HOUR_TO_SECOND       UInt8
# SQL_INTERVAL_MINUTE_TO_SECOND     SQL_C_INTERVAL_MINUTE_TO_SECOND     UInt8
# SQL_GUID                          SQL_C_GUID                          UUID

# SQL Data Type Definitions
const SQL_NULL_DATA     = -1
const SQL_NO_TOTAL      = -4
const SQL_CHAR          = Int16(  1) # Character string of fixed string length n.
const SQL_VARCHAR       = Int16( 12) # Variable-length character string with a maximum string length n.
const SQL_LONGVARCHAR   = Int16( -1) # Variable length character data. Maximum length is data source–dependent.
const SQL_WCHAR         = Int16( -8) # Unicode character string of fixed string length n
const SQL_WVARCHAR      = Int16( -9) # Unicode variable-length character string with a maximum string length n
const SQL_WLONGVARCHAR  = Int16(-10) # Unicode variable-length character data. Maximum length is data source–dependent
const SQL_DECIMAL       = Int16(  3)
const SQL_NUMERIC       = Int16(  2)
const SQL_SMALLINT      = Int16(  5) # Exact numeric value with precision 5 and scale 0 (signed: –32,768 <= n <= 32,767, unsigned: 0 <= n <= 65,535)
const SQL_INTEGER       = Int16(  4) # Exact numeric value with precision 10 and scale 0 (signed: –2[31] <= n <= 2[31] – 1, unsigned: 0 <= n <= 2[32] – 1)
const SQL_REAL          = Int16(  7) # Signed, approximate, numeric value with a binary precision 24 (zero or absolute value 10[–38] to 10[38]).
const SQL_FLOAT         = Int16(  6) # Signed, approximate, numeric value with a binary precision of at least p. (The maximum precision is driver-defined.)
const SQL_DOUBLE        = Int16(  8) # Signed, approximate, numeric value with a binary precision 53 (zero or absolute value 10[–308] to 10[308]).
const SQL_BIT           = Int16( -7) # Single bit binary data.
const SQL_TINYINT       = Int16( -6) # Exact numeric value with precision 3 and scale 0 (signed: –128 <= n <= 127, unsigned: 0 <= n <= 255)
const SQL_BIGINT        = Int16( -5) # Exact numeric value with precision 19 (if signed) or 20 (if unsigned) and scale 0 (signed: –2[63] <= n <= 2[63] – 1, unsigned: 0 <= n <= 2[64] – 1)
const SQL_BINARY        = Int16( -2) # Binary data of fixed length n.
const SQL_VARBINARY     = Int16( -3) # Variable length binary data of maximum length n. The maximum is set by the user.
const SQL_LONGVARBINARY = Int16( -4) # Variable length binary data. Maximum length is data source–dependent.
const SQL_TYPE_DATE     = Int16( 91) # Year, month, and day fields, conforming to the rules of the Gregorian calendar.
const SQL_TYPE_TIME     = Int16( 92) # Hour, minute, and second fields, with valid values for hours of 00 to 23,
                                     # valid values for minutes of 00 to 59, and valid values for seconds of 00 to 61. Precision p indicates the seconds precision.
const SQL_TYPE_TIMESTAMP = Int16( 93) # Year, month, day, hour, minute, and second fields, with valid values as defined for the DATE and TIME data types.
# SQL Server specific
const SQL_SS_TIME2       = Int16(-154)
const SQL_SS_TIMESTAMPOFFSET = Int16(-155)

#const SQL_INTERVAL_MONTH            = Int16(102)
#const SQL_INTERVAL_YEAR             = Int16(101)
#const SQL_INTERVAL_YEAR_TO_MONTH    = Int16(107)
#const SQL_INTERVAL_DAY              = Int16(103)
#const SQL_INTERVAL_HOUR             = Int16(104)
#const SQL_INTERVAL_MINUTE           = Int16(105)
#const SQL_INTERVAL_SECOND           = Int16(106)
#const SQL_INTERVAL_DAY_TO_HOUR      = Int16(108)
#const SQL_INTERVAL_DAY_TO_MINUTE    = Int16(109)
#const SQL_INTERVAL_DAY_TO_SECOND    = Int16(110)
#const SQL_INTERVAL_HOUR_TO_MINUTE   = Int16(111)
#const SQL_INTERVAL_HOUR_TO_SECOND   = Int16(112)
#const SQL_INTERVAL_MINUTE_TO_SECOND = Int16(113)
const SQL_GUID                      = Int16(-11) # Fixed length GUID.

# C Data Types
const SQL_C_CHAR      = Int16(  1)
const SQL_C_WCHAR     = Int16( -8)
const SQL_C_DOUBLE    = Int16(  8)
const SQL_C_SHORT     = Int16(  5)
const SQL_C_LONG      = Int16(  4)
const SQL_C_FLOAT     = Int16(  7)
const SQL_C_NUMERIC   = Int16(  2)
const SQL_C_BIT       = Int16( -7)
const SQL_C_TINYINT   = Int16( -6)
const SQL_C_BIGINT    = Int16(-27)
const SQL_C_BINARY    = Int16( -2)
const SQL_C_TYPE_DATE = Int16( 91)
const SQL_C_TYPE_TIME = Int16( 92)
const SQL_C_TYPE_TIMESTAMP = Int16( 93)
const SQL_SIGNED_OFFSET = Int16(-20)
const SQL_UNSIGNED_OFFSET = Int16(-22)
const SQL_C_SLONG = (SQL_C_LONG+SQL_SIGNED_OFFSET)
const SQL_C_SSHORT = (SQL_C_SHORT+SQL_SIGNED_OFFSET)
const SQL_C_STINYINT = (SQL_TINYINT+SQL_SIGNED_OFFSET)
const SQL_C_SBIGINT = (SQL_BIGINT+SQL_SIGNED_OFFSET)
const SQL_C_ULONG = (SQL_C_LONG+SQL_UNSIGNED_OFFSET)
const SQL_C_USHORT = (SQL_C_SHORT+SQL_UNSIGNED_OFFSET)
const SQL_C_UTINYINT = (SQL_TINYINT+SQL_UNSIGNED_OFFSET)
const SQL_C_UBIGINT = (SQL_BIGINT+SQL_UNSIGNED_OFFSET)

#const SQL_C_INTERVAL_MONTH            = Int16(102)
#const SQL_C_INTERVAL_YEAR             = Int16(101)
#const SQL_C_INTERVAL_YEAR_TO_MONTH    = Int16(107)
#const SQL_C_INTERVAL_DAY              = Int16(103)
#const SQL_C_INTERVAL_HOUR             = Int16(104)
#const SQL_C_INTERVAL_MINUTE           = Int16(105)
#const SQL_C_INTERVAL_SECOND           = Int16(106)
#const SQL_C_INTERVAL_DAY_TO_HOUR      = Int16(108)
#const SQL_C_INTERVAL_DAY_TO_MINUTE    = Int16(109)
#const SQL_C_INTERVAL_DAY_TO_SECOND    = Int16(110)
#const SQL_C_INTERVAL_HOUR_TO_MINUTE   = Int16(111)
#const SQL_C_INTERVAL_HOUR_TO_SECOND   = Int16(112)
#const SQL_C_INTERVAL_MINUTE_TO_SECOND = Int16(113)
const SQL_C_GUID                      = Int16(-11)

const SQL_C_SS_TIME2                    = Int16(16384)

"Convenience mapping of SQL types to their string representation"
const SQL_TYPES = Dict(
      1 => "SQL_CHAR",
     12 => "SQL_VARCHAR",
     -1 => "SQL_LONGVARCHAR",
     -8 => "SQL_WCHAR",
     -9 => "SQL_WVARCHAR",
    -10 => "SQL_WLONGVARCHAR",
      3 => "SQL_DECIMAL",
      2 => "SQL_NUMERIC",
      5 => "SQL_SMALLINT",
      4 => "SQL_INTEGER",
      7 => "SQL_REAL",
      6 => "SQL_FLOAT",
      8 => "SQL_DOUBLE",
     -7 => "SQL_BIT",
     -6 => "SQL_TINYINT",
     -5 => "SQL_BIGINT",
     -2 => "SQL_BINARY",
     -3 => "SQL_VARBINARY",
     -4 => "SQL_LONGVARBINARY",
     91 => "SQL_TYPE_DATE",
     92 => "SQL_TYPE_TIME",
     93 => "SQL_TYPE_TIMESTAMP",
   -154 => "SQL_SS_TIME2",
   -155 => "SQL_SS_TIMESTAMPOFFSET",
    102 => "SQL_INTERVAL_MONTH",
    101 => "SQL_INTERVAL_YEAR",
    107 => "SQL_INTERVAL_YEAR_TO_MONTH",
    103 => "SQL_INTERVAL_DAY",
    104 => "SQL_INTERVAL_HOUR",
    105 => "SQL_INTERVAL_MINUTE",
    106 => "SQL_INTERVAL_SECOND",
    108 => "SQL_INTERVAL_DAY_TO_HOUR",
    109 => "SQL_INTERVAL_DAY_TO_MINUTE",
    110 => "SQL_INTERVAL_DAY_TO_SECOND",
    111 => "SQL_INTERVAL_HOUR_TO_MINUTE",
    112 => "SQL_INTERVAL_HOUR_TO_SECOND",
    113 => "SQL_INTERVAL_MINUTE_TO_SECOND",
    -11 => "SQL_GUID",
    -154 => "SQL_SS_TIME2")

"Convenience mapping of SQL types to their C-type equivalent as a string"
const C_TYPES = Dict(
  SQL_C_CHAR => "SQL_C_CHAR",
  SQL_C_WCHAR => "SQL_C_WCHAR",
  SQL_C_DOUBLE => "SQL_C_DOUBLE",
  SQL_C_SHORT => "SQL_C_SHORT",
  SQL_C_LONG => "SQL_C_LONG",
  SQL_C_FLOAT => "SQL_C_FLOAT",
  SQL_C_NUMERIC => "SQL_C_NUMERIC",
  SQL_C_BIT => "SQL_C_BIT",
  SQL_C_TINYINT => "SQL_C_TINYINT",
  SQL_C_BIGINT => "SQL_C_BIGINT",
  SQL_C_BINARY => "SQL_C_BINARY",
  SQL_C_TYPE_DATE => "SQL_C_TYPE_DATE",
  SQL_C_TYPE_TIME => "SQL_C_TYPE_TIME",
  SQL_C_TYPE_TIMESTAMP => "SQL_C_TYPE_TIMESTAMP",
  SQL_SIGNED_OFFSET => "SQL_SIGNED_OFFSET",
  SQL_UNSIGNED_OFFSET => "SQL_UNSIGNED_OFFSET",
  SQL_C_SLONG => "SQL_C_SLONG",
  SQL_C_SSHORT => "SQL_C_SSHORT",
  SQL_C_STINYINT => "SQL_C_STINYINT",
  SQL_C_ULONG => "SQL_C_ULONG",
  SQL_C_USHORT => "SQL_C_USHORT",
  SQL_C_UTINYINT => "SQL_C_UTINYINT",
  SQL_C_GUID => "SQL_C_GUID",
  SQL_C_SS_TIME2 => "SQL_C_SS_TIME2",
  SQL_C_SBIGINT => "SQL_C_SBIGINT",
)

# success codes
const SQL_SUCCESS           = Int16(0)
const SQL_SUCCESS_WITH_INFO = Int16(1)

# error codes
const SQL_ERROR             = Int16(-1)
const SQL_INVALID_HANDLE    = Int16(-2)
const SQL_NTS               = -3

# status codes
const SQL_STILL_EXECUTING   = Int16(2)
const SQL_NO_DATA           = Int16(100)

const RETURN_VALUES = Dict(SQL_ERROR   => "SQL_ERROR",
                           SQL_NO_DATA => "SQL_NO_DATA",
                           SQL_SUCCESS => "SQL_SUCCESS",
                           SQL_NTS     => "SQL_NTS",
                           SQL_STILL_EXECUTING   => "SQL_STILL_EXECUTING",
                           SQL_INVALID_HANDLE    => "SQL_INVALID_HANDLE",
                           SQL_SUCCESS_WITH_INFO => "SQL_SUCCESS_WITH_INFO")

const SQL_NO_NULLS = Int16(0)
