#Link to ODBC Driver Manager (system-dependent)
@windows_only const odbc_dm = "odbc32"
@osx_only const odbc_dm = "libiodbc.dylib"
@linux_only const odbc_dm = "libodbc.so.1"

macro odbc()
odbc_dm
end

#SQL Constants (for readability and reference to ODBC API: http://goo.gl/l0Zin)
const SQL_HANDLE_ENV = 1  
const SQL_HANDLE_DBC = 2  
const SQL_HANDLE_STMT = 3  
const SQL_NULL_HANDLE = 0  
const SQL_NO_DATA = 100  
const SQL_NULL_DATA = -1
const SQL_SUCCESS = int16(0)
const SQL_SUCCESS_WITH_INFO = int16(1)
const SQL_ATTR_ODBC_VERSION = 200  
const SQL_OV_ODBC3 = uint(3)  
const SQL_IS_INTEGER = -6  
const SQL_NTS = -3  
const SQL_CLOSE = uint16(0)
const SQL_RESET_PARAMS = uint16(3)
const SQL_UNBIND = uint16(2)
const SQL_FETCH_NEXT = 1
const SQL_DRIVER_COMPLETE = 1
const SQL_DRIVER_COMPLETE_REQUIRED = 3
const SQL_DRIVER_NOPROMPT = 0
const SQL_DRIVER_PROMPT = 2
const SQL_ATTR_ROW_ARRAY_SIZE = 27

const MULTIROWFETCH = 1024 #Several drivers have an internal limit this size, = int(typemax(Uint16))

#SQL Data Types; C Data Types; Julia Types
#(*Note: SQL data types are returned in resultset metadata calls, and C data types are accepted by the DBMS for conversion)
#Data Type Status: Pretty good, I think we're at 90% support, really only missing native DATE, TIME, GUID. I think there are some other Time Interval types too, but I haven't researched it much.
#The other thing I haven't tested/played around with is Unicode support, I think we're reading it in right, but I'm not sure.
const SQL_TINYINT = const SQL_C_TINYINT = -6; #Int8
const SQL_SMALLINT = 5; #Int16
const SQL_C_SHORT = -15 #Int16
const SQL_INTEGER = 4; #Int32
const SQL_C_LONG = -16 #Int32
const SQL_REAL = 7; #Int32
const SQL_BIGINT = -5; #Int64
const SQL_C_BIGINT = -27; #Int64
#I originally thought of trying to reduce the float types to Ints if the metadata returned 0 column digits, but several drivers don't accurately return here, so Float64 is the default so no precision is lost
#An idea is to have DataFrames type inference support to reduce all these types to their smallest accurate representation
const SQL_DECIMAL = 3; #Float64
const SQL_NUMERIC = 2; #Float64
const SQL_FLOAT = 6; #Float64
const SQL_C_FLOAT = 7; #Float64
const SQL_DOUBLE = const SQL_C_DOUBLE = 8; #Float64

const SQL_CHAR = const SQL_C_CHAR = 1; #SQL and C data type for Uint8
const SQL_VARCHAR = 12; #Uint8
const SQL_LONGVARCHAR = -1; #Uint8
const SQL_WCHAR = -8; #Uint8
const SQL_WVARCHAR = -9; #Uint8
const SQL_WLONGVARCHAR = -10; #Uint8

const SQL_BIT = -7; #Int8 - Will be 0 or 1
const SQL_BINARY = -2; #Uint8 (should leave as-is once retrieved?)
const SQL_VARBINARY = -3; #Uint8 (should leave as-is once retrieved?)
const SQL_LONGVARBINARY = -4; #Uint8 (should leave as-is once retrieved?)

#For now, all other types are just interpreted as SQL_C_CHAR, Uint8 bytestrings
#const SQL_TYPE_DATE = 91 
#const SQL_TYPE_TIME = 92
#const SQL_TYPE_TIMESTAMP = 93