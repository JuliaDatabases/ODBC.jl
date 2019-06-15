using Libdl, Dates, Printf, DecFP, WeakRefStrings

# Link to ODBC Driver Manager (system-dependent)
const odbc_dm = let
    if !isdefined(@__MODULE__, :odbc_dm)
        Sys.islinux()   && (lib_choices = ["libodbc", "libodbc.so", "libodbc.so.1", "libodbc.so.2", "libodbc.so.3"])
        Sys.iswindows() && (lib_choices = ["odbc32"])
        Sys.isapple()   && (lib_choices = ["libodbc.2.dylib","libodbc.dylib","libiodbc","libiodbc.dylib","libiodbc.1.dylib","libiodbc.2.dylib","libiodbc.3.dylib"])
        Libdl.find_library(lib_choices)
    end
end

function setODBC(x)
    global odbc_dm
    odbc_dm = x
end

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

if occursin("iodbc", odbc_dm)
    const SQLWCHAR = UInt32
else
    # correct for windows + unixODBC
    const SQLWCHAR = Cushort
end

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

# provide lowercase conversion functions for all types
# e.g., sqlchar(x) = convert(SQLCHAR, x)

for t in [:SQLCHAR, :SQLSCHAR, :SQLWCHAR, :SQLDATE, :SQLDECIMAL,
          :SQLDOUBLE, :SQLFLOAT, :SQLINTEGER, :SQLUINTEGER,
          :SQLSMALLINT, :SQLUSMALLINT, :SQLLEN, :SQLULEN,
          :SQLSETPOSIROW, :SQLROWCOUNT, :SQLROWSETSIZE, :SQLTRANSID,
          :SQLROWOFFSET, :SQLNUMERIC, :SQLPOINTER, :SQLREAL, :SQLTIME,
          :SQLTIMESTAMP, :SQLVARCHAR, :SQLRETURN, :SQLHANDLE,
          :SQLHENV, :SQLHDBC, :SQLHSTMT, :SQLHDESC, :ULONG, :PULONG,
          :USHORT, :PUSHORT, :UCHAR, :PUCHAR, :PSZ, :SCHAR, :SDWORD,
          :SWORD, :UDWORD, :UWORD, :SLONG, :SSHORT, :SDOUBLE,
          :LDOUBLE, :SFLOAT, :PTR, :HENV, :HDBC, :HSTMT, :RETCODE,
          :SQLHWND]
    fn = Symbol(lowercase(string(t)))
    @eval $fn(x) = convert($t, x)
end

# Data Type Mappings
# SQL data types are returned in resultset metadata calls (ODBCMetadata)
# C data types are used in SQLBindCols (ODBCFetch) to allocate column memory; the driver manager converts from the SQL type to this C type in memory
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
# SQL_GUID                          SQL_C_GUID                          SQLGUID

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

# Julia mapping C structs
struct SQLDate <: Dates.AbstractTime
    year::Int16
    month::Int16
    day::Int16
end

Base.show(io::IO,x::SQLDate) = print(io,"$(x.year)-$(lpad(x.month,2,'0'))-$(lpad(x.day,2,'0'))")
SQLDate(x::Dates.Date) = SQLDate(Dates.yearmonthday(x)...)
SQLDate() = SQLDate(0,0,0)
import Base: ==
==(x::SQLDate, y::Dates.Date) = x.year == Dates.year(y) && x.month == Dates.month(y) && x.day == Dates.day(y)
==(y::Dates.Date, x::SQLDate) = x.year == Dates.year(y) && x.month == Dates.month(y) && x.day == Dates.day(y)
Dates.Date(x::SQLDate) = Dates.Date(x.year, x.month, x.day)

struct SQLTime <: Dates.AbstractTime
    hour::Int16
    minute::Int16
    second::Int16
end

Base.show(io::IO,x::SQLTime) = print(io,"$(lpad(x.hour,2,'0')):$(lpad(x.minute,2,'0')):$(lpad(x.second,2,'0'))")
SQLTime() = SQLTime(0,0,0)

struct SQLTimestamp <: Dates.AbstractTime
    year::Int16
    month::Int16
    day::Int16
    hour::Int16
    minute::Int16
    second::Int16
    fraction::Int32 #nanoseconds
end

Base.show(io::IO,x::SQLTimestamp) = print(io,"$(x.year)-$(lpad(x.month,2,'0'))-$(lpad(x.day,2,'0'))T$(lpad(x.hour,2,'0')):$(lpad(x.minute,2,'0')):$(lpad(x.second,2,'0'))$(x.fraction == 0 ? "" : strip(Printf.@sprintf("%.9f",x.fraction/1e+9),'0'))")
function SQLTimestamp(x::Dates.DateTime)
    y, m, d = Dates.yearmonthday(x)
    h, mm, s = Dates.hour(x), Dates.minute(x), Dates.second(x)
    frac = Dates.millisecond(x) * 1_000_000
    return SQLTimestamp(y, m, d, h, mm, s, frac)
end
SQLTimestamp() = SQLTimestamp(0,0,0,0,0,0,0)
==(x::SQLTimestamp, y::Dates.DateTime) = x.year == Dates.year(y) && x.month == Dates.month(y) && x.day == Dates.day(y) &&
                                   x.hour == Dates.hour(y) && x.minute == Dates.minute(y) && x.second == Dates.second(y)
==(y::Dates.DateTime, x::SQLTimestamp) = x.year == Dates.year(y) && x.month == Dates.month(y) && x.day == Dates.day(y) &&
                               x.hour == Dates.hour(y) && x.minute == Dates.minute(y) && x.second == Dates.second(y)
Dates.DateTime(x::SQLTimestamp) = Dates.DateTime(x.year, x.month, x.day, x.hour, x.minute, x.second, x.fraction ÷ 1_000_000)

const SQL_MAX_NUMERIC_LEN = 16
struct SQLNumeric
    precision::SQLCHAR
    scale::SQLSCHAR
    sign::SQLCHAR
    val::NTuple{SQL_MAX_NUMERIC_LEN,SQLCHAR}
end

Base.show(io::IO,x::SQLNumeric) = print(io,"SQLNumeric($(x.sign == 1 ? '+' : '-') precision: $(x.precision) scale: $(x.scale) val: $(x.val))")
SQLNumeric() = SQLNumeric(0,0,0,(0,))

# typedef struct  tagSQLGUID
# {
#     DWORD Data1;
#     WORD Data2;
#     WORD Data3;
#     BYTE Data4[ 8 ];
# } SQLGUID;
struct SQLGUID
    Data1::Cuint
    Data2::Cushort
    Data3::Cushort
    Data4::NTuple{8,Cuchar}
end

# for representing SQL LONG types
struct Long{T} end

"""
Dict for mapping SQL types to C types.
When executing an SQL query that returns results, the DBMS will return the SQL types of the resultset;
The application then tells the ODBC Driver Manager how to actually return the data
(by specifying the equivalent C type or something else entirely).
"""
const SQL2C = Dict(
    SQL_CHAR           => SQL_C_CHAR,
    SQL_VARCHAR        => SQL_C_CHAR,
    SQL_LONGVARCHAR    => SQL_C_CHAR,
    SQL_WCHAR          => SQL_C_WCHAR,
    SQL_WVARCHAR       => SQL_C_WCHAR,
    SQL_WLONGVARCHAR   => SQL_C_WCHAR,
    SQL_DECIMAL        => SQL_C_CHAR,
    SQL_NUMERIC        => SQL_C_CHAR,
    SQL_SMALLINT       => SQL_C_SHORT,
    SQL_INTEGER        => SQL_C_LONG,
    SQL_REAL           => SQL_C_FLOAT,
    SQL_FLOAT          => SQL_C_DOUBLE,
    SQL_DOUBLE         => SQL_C_DOUBLE,
    SQL_BIT            => SQL_C_BIT,
    SQL_TINYINT        => SQL_C_TINYINT,
    SQL_BIGINT         => SQL_C_BIGINT,
    SQL_BINARY         => SQL_C_BINARY,
    SQL_VARBINARY      => SQL_C_BINARY,
    SQL_LONGVARBINARY  => SQL_C_BINARY,
    SQL_TYPE_DATE      => SQL_C_TYPE_DATE,
    SQL_TYPE_TIME      => SQL_C_TYPE_TIME,
    SQL_TYPE_TIMESTAMP => SQL_C_TYPE_TIMESTAMP,
    SQL_SS_TIME2       => SQL_C_TYPE_TIME,
    SQL_SS_TIMESTAMPOFFSET => SQL_C_TYPE_TIMESTAMP,
    SQL_GUID           => SQL_C_GUID)

const julia2SQL = Dict(
    String                => SQL_CHAR,
    WeakRefString{UInt8}  => SQL_CHAR,
    WeakRefString{UInt16} => SQL_WCHAR,
    WeakRefString{UInt32} => SQL_WCHAR,
    Dec64                 => SQL_DOUBLE,
    Float16               => SQL_FLOAT,
    Float32               => SQL_FLOAT,
    Float64               => SQL_DOUBLE,
    Int8                  => SQL_TINYINT,
    Int16                 => SQL_SMALLINT,
    Int32                 => SQL_INTEGER,
    Int64                 => SQL_BIGINT,
    Bool                  => SQL_BIT,
    Vector{UInt8}         => SQL_BINARY,
    Dates.Date            => SQL_TYPE_DATE,
    Dates.DateTime        => SQL_TYPE_TIMESTAMP,
    SQLDate               => SQL_TYPE_DATE,
    SQLTime               => SQL_TYPE_TIME,
    SQLTimestamp          => SQL_TYPE_TIMESTAMP
)

const julia2C = Dict(
    String                => SQL_C_CHAR,
    WeakRefString{UInt8}  => SQL_C_CHAR,
    WeakRefString{UInt16} => SQL_C_WCHAR,
    WeakRefString{UInt32} => SQL_C_WCHAR,
    Dec64                 => SQL_C_DOUBLE,
    Float16               => SQL_C_FLOAT,
    Float32               => SQL_C_FLOAT,
    Float64               => SQL_C_DOUBLE,
    Int8                  => SQL_C_TINYINT,
    Int16                 => SQL_C_SHORT,
    Int32                 => SQL_C_LONG,
    Int64                 => SQL_C_BIGINT,
    Bool                  => SQL_C_BIT,
    Vector{UInt8}         => SQL_C_BINARY,
    Dates.Date            => SQL_C_TYPE_DATE,
    Dates.DateTime        => SQL_C_TYPE_TIMESTAMP,
    SQLDate               => SQL_C_TYPE_DATE,
    SQLTime               => SQL_C_TYPE_TIME,
    SQLTimestamp          => SQL_C_TYPE_TIMESTAMP
)

"""
maps SQL types from the ODBC manager to Julia types;
in particular, it returns a Tuple{A,B,Bool}, where `A` is the Julia type
used to allocate and return data from the ODBC manager, while `B`
represents the final column type of the data; conversion from `A` to `B` happens
through the `cast(::Type{B})` function in utils.jl.
The 3rd `Bool` value indicates whether the column is a LONGTEXT or LONGBINARY SQL types, since these
tend to require special result-handling rules.
"""
const SQL2Julia = Dict(
    SQL_CHAR           => (SQLCHAR, Union{String, Missing}, false),
    SQL_VARCHAR        => (SQLCHAR, Union{String, Missing}, false),
    SQL_LONGVARCHAR    => (SQLCHAR, Union{String, Missing}, true),
    SQL_WCHAR          => (SQLWCHAR, Union{String, Missing}, false),
    SQL_WVARCHAR       => (SQLWCHAR, Union{String, Missing}, false),
    SQL_WLONGVARCHAR   => (SQLWCHAR, Union{String, Missing}, true),
    SQL_DECIMAL        => (SQLCHAR, Union{Dec64, Missing}, false),
    SQL_NUMERIC        => (SQLCHAR, Union{Dec64, Missing}, false),
    SQL_SMALLINT       => (SQLSMALLINT, Union{SQLSMALLINT, Missing}, false),
    SQL_INTEGER        => (SQLINTEGER,  Union{SQLINTEGER, Missing}, false),
    SQL_REAL           => (SQLREAL,   Union{SQLREAL, Missing}, false),
    SQL_FLOAT          => (SQLFLOAT,  Union{SQLFLOAT, Missing}, false),
    SQL_DOUBLE         => (SQLDOUBLE, Union{SQLDOUBLE, Missing}, false),
    SQL_BIT            => (Int8,  Union{Int8, Missing}, false),
    SQL_TINYINT        => (Int8,  Union{Int8, Missing}, false),
    SQL_BIGINT         => (Int64, Union{Int64, Missing}, false),
    SQL_BINARY         => (UInt8, Union{Vector{UInt8}, Missing}, false),
    SQL_VARBINARY      => (UInt8, Union{Vector{UInt8}, Missing}, false),
    SQL_LONGVARBINARY  => (UInt8, Union{Vector{UInt8}, Missing}, true),
    SQL_TYPE_DATE      => (SQLDate, Union{SQLDate, Missing}, false),
    SQL_TYPE_TIME      => (SQLTime, Union{SQLTime, Missing}, false),
    SQL_TYPE_TIMESTAMP => (SQLTimestamp, Union{SQLTimestamp, Missing}, false),
    SQL_SS_TIME2       => (SQLTime, Union{SQLTime, Missing}, false),
    SQL_SS_TIMESTAMPOFFSET => (SQLTimestamp, Union{SQLTimestamp, Missing}, false),
    SQL_GUID           => (SQLGUID, Union{SQLGUID, Missing}, false))

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
    -11 => "SQL_GUID")

"Convenience mapping of SQL types to their C-type equivalent as a string"
const C_TYPES = Dict(
    SQL_CHAR           => "SQL_C_CHAR",
    SQL_VARCHAR        => "SQL_C_CHAR",
    SQL_LONGVARCHAR    => "SQL_C_CHAR",
    SQL_WCHAR          => "SQL_C_WCHAR",
    SQL_WVARCHAR       => "SQL_C_WCHAR",
    SQL_WLONGVARCHAR   => "SQL_C_WCHAR",
    SQL_DECIMAL        => "SQL_C_NUMERIC",
    SQL_NUMERIC        => "SQL_C_NUMERIC",
    SQL_SMALLINT       => "SQL_C_SHORT",
    SQL_INTEGER        => "SQL_C_LONG",
    SQL_REAL           => "SQL_C_FLOAT",
    SQL_FLOAT          => "SQL_C_DOUBLE",
    SQL_DOUBLE         => "SQL_C_DOUBLE",
    SQL_BIT            => "SQL_C_BIT",
    SQL_TINYINT        => "SQL_C_TINYINT",
    SQL_BIGINT         => "SQL_C_BIGINT",
    SQL_BINARY         => "SQL_C_BINARY",
    SQL_VARBINARY      => "SQL_C_BINARY",
    SQL_LONGVARBINARY  => "SQL_C_BINARY",
    SQL_TYPE_DATE      => "SQL_C_TYPE_DATE",
    SQL_TYPE_TIME      => "SQL_C_TYPE_TIME",
    SQL_TYPE_TIMESTAMP => "SQL_C_TYPE_TIMESTAMP",
    SQL_C_GUID         => "SQL_C_GUID")
