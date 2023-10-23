using DBInterface
using ODBC
using Test
# using DataFrames

if Sys.islinux()
    # this is the install location for the devcontainer feature, probably wrong here
    ODBC.adddriver("ODBC Driver 18 for SQL Server", "/opt/microsoft/msodbcsql18/lib64/libmsodbcsql-18.3.so.2.1")
elseif Sys.iswindows()
    # Assume driver is installed in OS already
else
#    libpath = MariaDB_Connector_ODBC_jll.libmaodbc_path
end

mssql = ODBC.Connection("Driver={ODBC Driver 18 for SQL Server};Server=msdb;Encrypt=no", "sa", "msSQ_F123")

res = DBInterface.execute(mssql, 
"SELECT CONVERT(uniqueidentifier, 'ABCD0000-0000-0000-1234-000000000000') AS anid, 'ABCD0000-0000-0000-1234-000000000000' AS strid",
debug=true)

r = first(res)
@show r
@show string(r.anid)
@show Base.UUID(string(r.anid))
@test string(r.anid) == "abcd0000-0000-0000-1234-000000000000"
@test Base.UUID(r.anid) == Base.UUID("abcd0000-0000-0000-1234-000000000000")


# ODBC.Row:
#  :anid   UUID("00000000-0000-3412-0000-0000abcd0000")
#  :strid  "ABCD0000-0000-0000-1234-000000000000"