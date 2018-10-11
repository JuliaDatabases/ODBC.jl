using Test, Dates, Random, ODBC, Tables, WeakRefStrings, DataFrames, DecFP, CSV, SQLite

# You can also specify which database you want to test for as an environment variable:
# ENV["ODBC_TEST_DRIVERS"] = "mysql"
const TEST_DRIVERS = split(get(ENV, "ODBC_TEST_DRIVERS", "mysql, postgresql, mssql"), r"\s*,\s*")
const TEST_MYSQL = "mysql" in TEST_DRIVERS
const TEST_POSTGRESQL = "postgresql" in TEST_DRIVERS
const TEST_MSSQL = "mssql" in TEST_DRIVERS

# To run these tests first run these statements from the command line in the ODBC root directory:
# odbcinst -i -s -h -f test/setup/mysqltest.odbc.ini
# odbcinst -i -s -h -f test/setup/postgresqltest.odbc.ini
# odbcinst -i -s -h -f test/setup/mssqltest.odbc.ini

# You can modify the above files as needed to point to your mysql, postgres, or mssql
# database and drivers, or to specify your username and password

# To setup docker containers to test against you can run:
# docker run --name mysql -p 3306:3306  -e MYSQL_ALLOW_EMPTY_PASSWORD=true -d mysql
# docker run --name postgres -p 5432:5432 -e POSTGRES_PASSWORD="" -d postgres
# docker run --name mssql -e ACCEPT_EULA=Y -e 'MSSQL_SA_PASSWORD=YourStrong!Passw0rd' -p 1433:1433 -d microsoft/mssql-server-linux:2017-GDR

# You will also have needed to install drivers for mysql, postgres, and mssql and add those
# to your local odbcinst.ini file. For example:
# [MySQL]
# Description = MySQL driver
# Driver = /usr/local/lib/libmyodbc5a.so
# FileUsage = 1

# [PostgreSQL ANSI]
# Description = ODBC for PostgreSQL 9.6 ANSI
# Driver = /usr/local/lib/psqlodbca.so
# FileUsage = 1

# [ODBC Driver 13 for SQL Server]
# Description=Microsoft ODBC Driver 13 for SQL Server
# Driver=/usr/local/lib/libmsodbcsql.13.dylib
# UsageCount=1

@testset "ODBC.jl" begin

    @show TEST_DRIVERS
    @show ODBC.drivers()
    @show ODBC.dsns()
    @show ODBC.API.odbc_dm
    @show run(`odbcinst -q -d`)
    run(`uname -a`)

    if TEST_MYSQL
        include("mysql.jl")
    else
        @warn "Skipping mysql tests..."
    end

    if TEST_POSTGRESQL
        include("postgresql.jl")
    else
        @warn "Skipping postgresql tests..."
    end

    if TEST_MSSQL
        include("mssql.jl")
    else
        @warn "Skipping mssql tests..."
    end
end

