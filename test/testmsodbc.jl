using DBInterface
using ODBC
using Test
using Dates, DecFP
using Tables
using DataFrames

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




conn = DBInterface.connect(ODBC.Connection, "Driver={ODBC Driver 18 for SQL Server};Server=msdb;Encrypt=no", "sa", "msSQ_F123")

DBInterface.execute(conn, "
IF EXISTS (
    SELECT name
    FROM sys.databases
    WHERE name = N'mysqltest'
)
BEGIN
    USE master;
    ALTER DATABASE mysqltest
    SET SINGLE_USER
    WITH ROLLBACK IMMEDIATE;
    DROP DATABASE mysqltest;
END
")

# Must specify a collation with UTF-8 in order to enable UTF-8!
DBInterface.execute(conn, "CREATE DATABASE mysqltest COLLATE LATIN1_GENERAL_100_CI_AS_SC_UTF8")
DBInterface.execute(conn, "use mysqltest")
DBInterface.execute(conn, """

CREATE TABLE Employee
(
    ID INT IDENTITY(1,1) NOT NULL,
    OfficeNo TINYINT,
    DeptNo SMALLINT,
    EmpNo BIGINT,
    Wage DECIMAL(7, 2),
    Salary FLOAT,
    Rate DECIMAL(5, 3),
    LunchTime TIME,
    JoinDate DATE,
    LastLogin DATETIME,
    LastLogin2 DATETIME NOT NULL DEFAULT GETDATE(),
    Initial CHAR(1),
    Name NVARCHAR(255),
    Photo VARBINARY(MAX),
    JobType VARCHAR(255) CHECK (JobType IN ('HR', 'Management', 'Accounts')),
    Senior BIT,
    Uuidid UNIQUEIDENTIFIER,
    PRIMARY KEY (ID)
);

""")

DBInterface.execute(conn, """INSERT INTO Employee (OfficeNo, DeptNo, EmpNo, Wage, Salary, Rate, LunchTime, JoinDate, LastLogin, LastLogin2, Initial, Name, Photo, JobType, Senior, Uuidid)
                 VALUES
                 (1, 2, 1301, 3.14, 10000.50, 1.001, '12:00:00', '2015-8-3', '2015-9-5 12:31:30', '2015-9-5 12:31:30', 'A', 'John', 0xabcd, 'HR', '1', '123e4567-e89b-12d3-a456-426655440000'),
                 (1, 2, 1422, 3.14, 20000.25, 2.002, '13:00:00', '2015-8-4', '2015-10-12 13:12:14', '2015-10-12 13:12:14', 'B', 'Tom', 0xdeff, 'HR', '1', '11223344-5566-7788-99aa-bbccddeeff00'),
                 (1, 2, 1567, 3.14, 30000.00, 3.003, '12:30:00', '2015-6-2', '2015-9-5 10:05:10', '2015-9-5 10:05:10', 'C', 'Åsmund', 0x1234, 'Management', '0', '11223344-5566-7788-99aa-bbccddeeff01'),
                 (1, 2, 3200, 3.14, 15000.50, 2.5, '12:30:00', '2015-7-25', '2015-10-10 12:12:25', '2015-10-10 12:12:25', 'D', '望研測来白制父委供情治当認米注。規', 0x4567, 'Accounts', '1', '11223344-5566-7788-99aa-bbccddeeff02');
              """)

expected = (
  ID         = Int32[1, 2, 3, 4],
  OfficeNo   = Union{Missing, Int8}[1, 1, 1, 1],
  DeptNo     = Union{Missing, Int16}[2, 2, 2, 2],
  EmpNo      = Union{Missing, Int64}[1301, 1422, 1567, 3200],
  Wage       = Union{Missing, Dec64}[3.14, 3.14, 3.14, 3.14],
  Salary     = Union{Missing, Float64}[10000.5, 20000.25, 30000.0, 15000.5],
  Rate       = Union{Missing, Dec64}[d64"1.001", d64"2.002", d64"3.003", d64"2.5"],
  LunchTime  = Union{Missing, String}["12:00:00.0000000", "13:00:00.0000000", "12:30:00.0000000", "12:30:00.0000000"],  # @TODO this is wrong, but at least better than many options
  JoinDate   = Union{Missing, Dates.Date}[Date("2015-08-03"), Date("2015-08-04"), Date("2015-06-02"), Date("2015-07-25")],
  LastLogin  = Union{Missing, Dates.DateTime}[DateTime("2015-09-05T12:31:30"), DateTime("2015-10-12T13:12:14"), DateTime("2015-09-05T10:05:10"), DateTime("2015-10-10T12:12:25")],
  LastLogin2 = Dates.DateTime[DateTime("2015-09-05T12:31:30"), DateTime("2015-10-12T13:12:14"), DateTime("2015-09-05T10:05:10"), DateTime("2015-10-10T12:12:25")],
  Initial    = Union{Missing, String}["A", "B", "C", "D"],
  Name       = Union{Missing, String}["John", "Tom", "Åsmund", "望研測来白制父委供情治当認米注。規"],
  Photo      = Union{Missing, Vector{UInt8}}[UInt8[0xab, 0xcd], UInt8[0xde, 0xff], UInt8[0x12, 0x34], UInt8[0x45, 0x67]],
  JobType    = Union{Missing, String}["HR", "HR", "Management", "Accounts"],
  Senior     = Union{Missing, Bool}[true, true, false, true],
  Uuidid     = Union{Missing, Base.UUID}[
    Base.UUID("123e4567-e89b-12d3-a456-426655440000"),
    Base.UUID("11223344-5566-7788-99aa-bbccddeeff00"),
    Base.UUID("11223344-5566-7788-99aa-bbccddeeff01"),
    Base.UUID("11223344-5566-7788-99aa-bbccddeeff02")
  ]
)


# Validate that iteration of results throws runtime Error on DivisionByZero
@test_throws ErrorException DBInterface.execute(
    conn, "SELECT a, b, a/b FROM (VALUES (2,1),(1,0),(2,1)) AS t(a,b)"
) |> columntable

cursor = DBInterface.execute(conn, "select * from Employee");
@test eltype(cursor) == ODBC.Row
@test Tables.istable(cursor)
@test Tables.rowaccess(cursor)
@test Tables.rows(cursor) === cursor

resultschema = Tables.schema(cursor)
expectedschema = Tables.Schema(propertynames(expected), eltype.(collect(expected)))
for (rn,rt,en,et) in zip(resultschema.names, resultschema.types, expectedschema.names, expectedschema.types)
    @test rn == en
    @test rt == et
end

@test Tables.schema(cursor) == Tables.Schema(propertynames(expected), eltype.(collect(expected)))
#@test Base.IteratorSize(typeof(cursor)) == Base.HasLength()
#@test length(cursor) == 4

row = first(cursor)
@test Base.IndexStyle(typeof(row)) == Base.IndexLinear()
@test length(row) == length(expected)
@test propertynames(row) == collect(propertynames(expected))
for (i, prop) in enumerate(propertynames(row))
    #TODO fix this. Have no idea why getproperty returns the API.GUID type. 
    #@test getproperty(row, prop) == row[prop] == row[i] == expected[prop][1]
end
# As dataframes, it works, though:
dataframe = DBInterface.execute(conn, "select * from Employee") |> DataFrame
@test dataframe == DataFrame(expected)

res = DBInterface.execute(conn, "select * from Employee") |> columntable
@test length(res) == 17
@test length(res[1]) == 4
for (r,e) in zip(res,expected)
    @test r == e
end

# as a prepared statement
stmt = DBInterface.prepare(conn, "select * from Employee")
cursor = DBInterface.execute(stmt);
@test eltype(cursor) == ODBC.Row
@test Tables.istable(cursor)
@test Tables.rowaccess(cursor)
@test Tables.rows(cursor) === cursor
@test Tables.schema(cursor) == Tables.Schema(propertynames(expected), eltype.(collect(expected)))
#@test Base.IteratorSize(typeof(cursor)) == Base.HasLength()
#@test length(cursor) == 4

row = first(cursor);
@test Base.IndexStyle(typeof(row)) == Base.IndexLinear()
@test length(row) == length(expected)
@test propertynames(row) == collect(propertynames(expected))
for (i, prop) in enumerate(propertynames(row))
#    @test getproperty(row, prop) == row[prop] == row[i] == expected[prop][1]
end

res = DBInterface.execute(stmt) |> columntable
@test length(res) == 17
@test length(res[1]) == 4
@test res == expected

@test DBInterface.close!(stmt) === nothing
@test_throws ErrorException DBInterface.execute(stmt)

# insert null row
DBInterface.execute(conn, "INSERT INTO Employee DEFAULT VALUES;")
for i = 1:length(expected)
    if i == 1
        push!(expected[i], 5)
    elseif i == 11
    else
        push!(expected[i], missing)
    end
end

res = DBInterface.execute(conn, "select * from Employee") |> columntable
@test length(res) == 17
@test length(res[1]) == 5
for i = 1:length(expected)
    if i != 11
        @test isequal(res[i], expected[i])
    end
end

stmt = DBInterface.prepare(conn, "select * from Employee")
res = DBInterface.execute(stmt) |> columntable
DBInterface.close!(stmt)
@test length(res) == 17
@test length(res[1]) == 5
for i = 1:length(expected)
    if i != 11
        @test isequal(res[i], expected[i])
    end
end

# # ODBC.load
# ODBC.load(Base.structdiff(expected, NamedTuple{(:LastLogin2, :Wage,)}), conn, "EmployeeCopy"; limit=4)
# res = DBInterface.execute(conn, "select * from Employee_copy") |> columntable
# @test length(res) == 14
# @test length(res[1]) == 4
# for nm in keys(res)
#     @test isequal(res[nm], expected[nm][1:4])
# end

# now test insert/parameter binding
DBInterface.execute(conn, "DELETE FROM Employee")
for i = 1:length(expected)
    if i != 11
        pop!(expected[i])
    end
end

stmt = DBInterface.prepare(conn,
    "INSERT INTO Employee (OfficeNo, DeptNo, EmpNo, Wage, Salary, Rate, LunchTime, JoinDate, LastLogin, LastLogin2, Initial, Name, Photo, JobType, Senior, Uuidid)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")

DBInterface.executemany(stmt, Base.structdiff(expected, NamedTuple{(:ID,)}))

stmt2 = DBInterface.prepare(conn, "select * from Employee")
res = DBInterface.execute(stmt2) |> columntable
DBInterface.close!(stmt2)
@test length(res) == 17
@test length(res[1]) == 4
for i = 1:length(expected)
    if i != 11 && i != 1
        @test isequal(res[i], expected[i])
    end
end

DBInterface.execute(stmt, [missing, missing, missing, missing, missing, missing, missing, missing, missing, DateTime("2015-09-05T12:31:30"), missing, missing, missing, missing, missing])
DBInterface.close!(stmt)

stmt = DBInterface.prepare(conn, "select * from Employee")
res = DBInterface.execute(stmt; ignore_driver_row_count=true) |> columntable
DBInterface.close!(stmt)
for i = 1:length(expected)
    if i != 11 && i != 1
        @test res[i][end] === missing
    end
end

DBInterface.execute(conn, """
CREATE PROCEDURE get_employee()
BEGIN
   select * from Employee;
END
""")
res = DBInterface.execute(conn, "call get_employee()") |> columntable
@test length(res) > 0
@test length(res[1]) == 5
res = DBInterface.execute(conn, "call get_employee()") |> columntable
@test length(res) > 0
@test length(res[1]) == 5
# test that we can call multiple stored procedures in a row w/o collecting results (they get cleaned up properly internally)
res = DBInterface.execute(conn, "call get_employee()")
res = DBInterface.execute(conn, "call get_employee()")

# and for prepared statements
stmt = DBInterface.prepare(conn, "call get_employee()")
res = DBInterface.execute(stmt) |> columntable
@test length(res) > 0
@test length(res[1]) == 5
res = DBInterface.execute(stmt) |> columntable
@test length(res) > 0
@test length(res[1]) == 5
res = DBInterface.execute(stmt)
res = DBInterface.execute(stmt)

results = DBInterface.executemultiple(conn, """
select ID from Employee;
select DeptNo, OfficeNo from Employee where OfficeNo IS NOT NULL
""")
state = iterate(results)
@test state !== nothing
res, st = state
@test !st
# @test_broken length(res) == 5
ret = columntable(res)
# @test_broken length(ret[1]) == 5
state = iterate(results, st)
@test state !== nothing
res, st = state
@test !st
# @test_broken length(res) == 4
ret = columntable(res)
# @test_broken length(ret[1]) == 4

DBInterface.execute(conn, """CREATE TABLE Employee2
                 (
                     ID INT NOT NULL AUTO_INCREMENT,
                     望研 VARCHAR(255) CHARACTER SET utf8mb4,
                     PRIMARY KEY (ID)
                 )""")
DBInterface.execute(conn, "INSERT INTO Employee2 (望研) VALUES ('hey'), ('ho')")
ret = DBInterface.execute(conn, "select * from Employee2") |> columntable
@test length(ret.望研) == 2

DBInterface.execute(conn, """CREATE TABLE big_decimal
                 (
                     ID INT NOT NULL AUTO_INCREMENT,
                     `dec` DECIMAL(20, 2),
                     PRIMARY KEY (ID)
                 )""")
DBInterface.execute(conn, "INSERT INTO big_decimal (`dec`) VALUES (123456789012345678.91)")
ret = DBInterface.execute(conn, "select * from big_decimal") |> columntable
@test ret.dec[1] == d128"1.2345678901234567891e17"

ret = ODBC.tables(conn, tablename="emp%") |> columntable
@test ret.TABLE_NAME == ["Employee", "Employee2", "Employee_copy"]
ret = ODBC.columns(conn, tablename="emp%", columnname="望研") |> columntable
@test ret.COLUMN_NAME == ["望研"]

DBInterface.execute(conn, """DROP USER IF EXISTS 'authtest'""")
DBInterface.execute(conn, """CREATE USER 'authtest' IDENTIFIED BY 'authtestpw'""")

connstrconn = DBInterface.connect(ODBC.Connection, "Driver={ODBC Driver 18 for SQL Server};SERVER=127.0.0.1;PLUGIN_DIR=$PLUGIN_DIR;Option=67108864;CHARSET=utf8mb4"; user="authtest", password="authtestpw")
@test connstrconn.dsn == "Driver={ODBC Driver 18 for SQL Server};SERVER=127.0.0.1;PLUGIN_DIR=$PLUGIN_DIR;Option=67108864;CHARSET=utf8mb4"
ret = DBInterface.execute(connstrconn, "select current_user() as user") |> columntable
@test startswith(ret.user[1], "authtest@")
DBInterface.close!(connstrconn)

DBInterface.close!(conn)


