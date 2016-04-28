reload("ODBC")

@show ODBC.listdrivers()
@show ODBC.listdsns()

dsn = ODBC.DSN("")

# Check some basic queries
dbs = ODBC.query(dsn, "show databases")
ODBC.query(dsn, "use mysql")
data = ODBC.query(dsn, "select table_name from information_schema.tables");

# setup a test database
# ODBC.Source(dsn, "drop database if exists testdb")
# ODBC.Source(dsn, "create database testdb")
ODBC.Source(dsn, "use testdb")
ODBC.Source(dsn, "drop table if exists test1")
ODBC.Source(dsn, "create table test1
                    (test_bigint bigint,
                     test_bit bit,
                     test_decimal decimal,
                     test_int int,
                     test_numeric numeric,
                     test_smallint smallint,
                     test_mediumint mediumint,
                     test_tiny_int tinyint,
                     test_float float,
                     test_real double,
                     test_date date,
                     test_datetime datetime,
                     test_timestamp timestamp,
                     test_time time,
                     test_year year,
                     test_char char(1),
                     test_varchar varchar(16),
                     test_binary binary(2),
                     test_varbinary varbinary(16),
                     test_tinyblob tinyblob,
                     test_blob blob,
                     test_mediumblob mediumblob,
                     test_longblob longblob,
                     test_tinytext tinytext,
                     test_text text,
                     test_mediumtext mediumtext,
                     test_longtext longtext
                    )")
data = ODBC.query(dsn, "select * from information_schema.columns where table_name = 'test1'")
ODBC.Source(dsn, "insert test1 VALUES
                    (1, -- bigint
                     1, -- bit
                     1.0, -- decimal
                     1, -- int
                     1.0, -- numeric
                     1, -- smallint
                     1, -- mediumint
                     1, -- tinyint
                     1.2, -- float
                     1.2, -- double
                     '2016-01-01', -- date
                     '2016-01-01 01:01:01', -- datetime
                     '2016-01-01 01:01:01-05:00', -- timestamp
                     '01:01:01', -- time
                     2016, -- year
                     'A', -- char(1)
                     'hey there sailor', -- varchar
                     cast(123456 as binary(2)), -- binary
                     NULL, -- varbinary
                     'hey there abraham', -- tinyblob
                     'hey there bill', -- blob
                     'hey there charlie', -- mediumblob
                     'hey there dan', -- longblob
                     'hey there ephraim', -- tinytext
                     'hey there frank', -- text
                     'hey there george', -- mediumtext
                     'hey there hank' -- longtext
                    )")
source = ODBC.Source(dsn, "select * from test1")
data = Data.stream!(source, Data.Table)
@test size(data) == (1,27)
@test data.schema.types ==
[Int64,
 Int8,
 DecFP.Dec64,
 Int32,
 DecFP.Dec64,
 Int16,
 Int32,
 Int8,
 Float32,
 Float64,
 ODBC.API.SQLDate,
 ODBC.API.SQLTimestamp,
 ODBC.API.SQLTimestamp,
 ODBC.API.SQLTime,
 Int16,
 Data.PointerString{UInt8},
 Data.PointerString{UInt8},
 Array{UInt8,1},
 Array{UInt8,1},
 Array{UInt8,1},
 Array{UInt8,1},
 Array{UInt8,1},
 Array{UInt8,1},
 Data.PointerString{UInt8},
 Data.PointerString{UInt8},
 Data.PointerString{UInt8},
 Data.PointerString{UInt8}]
@test data.data[1][1] === Nullable(Int64(1))
@test data.data[2][1] === Nullable(Int8(1))
@test data.data[3][1] === Nullable(ODBC.DecFP.Dec64(1))
@test data.data[4][1] === Nullable(Int32(1))
@test data.data[5][1] === Nullable(ODBC.DecFP.Dec64(1))
@test data.data[6][1] === Nullable(Int16(1))
@test data.data[7][1] === Nullable(Int32(1))
@test data.data[8][1] === Nullable(Int8(1))
@test data.data[9][1] === Nullable(Float32(1.2))
@test data.data[10][1] === Nullable(Float64(1.2))
@test data.data[11][1] === Nullable(ODBC.API.SQLDate(2016,1,1))
@test data.data[12][1] === Nullable(ODBC.API.SQLTimestamp(2016,1,1,1,1,1,0))
@test data.data[13][1] === Nullable(ODBC.API.SQLTimestamp(2016,1,1,1,1,1,0))
@test data.data[14][1] === Nullable(ODBC.API.SQLTime(1,1,1))
@test data.data[15][1] === Nullable(Int16(2016))
@test string(get(data.data[16][1])) == "A"
@test string(get(data.data[17][1])) == "hey there sailor"
@test get(data.data[18][1]) == UInt8[0x31,0x32]
@test isnull(data.data[19][1])
@test get(data.data[20][1]) == UInt8[0x68,0x65,0x79,0x20,0x74,0x68,0x65,0x72,0x65,0x20,0x61,0x62,0x72,0x61,0x68,0x61,0x6d]
@test get(data.data[21][1]) == UInt8[0x68,0x65,0x79,0x20,0x74,0x68,0x65,0x72,0x65,0x20,0x62,0x69,0x6c,0x6c]
@test get(data.data[22][1]) == UInt8[0x68,0x65,0x79,0x20,0x74,0x68,0x65,0x72,0x65,0x20,0x63,0x68,0x61,0x72,0x6c,0x69,0x65]
@test get(data.data[23][1]) == UInt8[0x68,0x65,0x79,0x20,0x74,0x68,0x65,0x72,0x65,0x20,0x64,0x61,0x6e]
@test string(get(data.data[24][1])) == "hey there ephraim"
@test string(get(data.data[25][1])) == "hey there frank"
@test string(get(data.data[26][1])) == "hey there george"
@test string(get(data.data[27][1])) == "hey there hank"

ODBC.Source(dsn, "insert test1 VALUES
                    (1, -- bigint
                     1, -- bit
                     1.0, -- decimal
                     1, -- int
                     1.0, -- numeric
                     1, -- smallint
                     1, -- mediumint
                     1, -- tinyint
                     1.2, -- float
                     1.2, -- double
                     '2016-01-01', -- date
                     '2016-01-01 01:01:01', -- datetime
                     '2016-01-01 01:01:01-05:00', -- timestamp
                     '01:01:01', -- time
                     2016, -- year
                     'A', -- char(1)
                     'hey there sailor', -- varchar
                     cast(123456 as binary(2)), -- binary
                     NULL, -- varbinary
                     'hey there abraham', -- tinyblob
                     'hey there bill', -- blob
                     'hey there charlie', -- mediumblob
                     'hey there dan', -- longblob
                     'hey there ephraim', -- tinytext
                     'hey there frank', -- text
                     'hey there george', -- mediumtext
                     'hey there hank' -- longtext
                    )")
data = ODBC.query(dsn, "select * from test1")
@test size(data) == (2,27)


# ODBC.execute!(dsn, """
# CREATE TABLE test2
# (
#     ID INT NOT NULL PRIMARY KEY,
#     Name VARCHAR(25),
#     Salary DECIMAL,
#     Date DATE,
#     DeptNo SMALLINT,
#     DeptBudget FLOAT
# );""")
# @time for i = ODBC.API.MAXFETCHSIZE+1:ODBC.API.MAXFETCHSIZE+10
#     ODBC.execute!(dsn, """
#     INSERT INTO test2 (ID, Name, Salary, Date, DeptNo, DeptBudget)
#      VALUES ($i, 'John', 10000.50, '2015-08-03', 1301, 30000.0)
#     """)
#     i % 1000 == 0 && println(i)
# end
source = ODBC.Source(dsn, "select `salary` from test2 limit 10")
data = Data.stream!(source, Data.Table)
data = ODBC.query(dsn, "select count(*) from test2")
@test size(data) == (1,1)
@test data.data[1][1] === Nullable(65545)

@time data = ODBC.query(dsn, "select * from test2");
@test size(data)

@time data = ODBC.query(dsn, "select * from test1");
source = ODBC.Source(dsn, "select * from test1")
data = Data.stream!(source, Data.Table)

# test exporting test1 to CSV
source = ODBC.Source(dsn, "select * from test1")
csv = CSV.Sink("test1.csv")
Data.stream!(source, csv)
open("test1.csv") do f
    @test readline(f) == "\"test_bigint\",\"test_bit\",\"test_decimal\",\"test_int\",\"test_numeric\",\"test_smallint\",\"test_mediumint\",\"test_tiny_int\",\"test_float\",\"test_real\",\"test_date\",\"test_datetime\",\"test_timestamp\",\"test_time\",\"test_year\",\"test_char\",\"test_varchar\",\"test_binary\",\"test_varbinary\",\"test_tinyblob\",\"test_blob\",\"test_mediumblob\",\"test_longblob\",\"test_tinytext\",\"test_text\",\"test_mediumtext\",\"test_longtext\"\n"
    @test readline(f) == "1,1,+1E+0,1,+1E+0,1,1,1,1.2,1.2,2016-01-01,2016-01-01T01:01:01 ,2016-01-01T01:01:01 ,01:01:01,2016,\"A\",\"hey there sailor\",UInt8[49,50],\"\",UInt8[104,101,121,32,116,104,101,114,101,32,97,98,114,97,104,97,109],UInt8[104,101,121,32,116,104,101,114,101,32,98,105,108,108],UInt8[104,101,121,32,116,104,101,114,101,32,99,104,97,114,108,105,101],UInt8[104,101,121,32,116,104,101,114,101,32,100,97,110],\"hey there ephraim\",\"hey there frank\",\"hey there george\",\"hey there hank\"\n"
end

# # test exporting test2 to CSV
# source = ODBC.Source(dsn, "select * from test2")
# csv = CSV.Sink("test2.csv")
# Data.stream!(source, csv)

# test exporting test1 to SQLite
db = SQLite.DB()
source = ODBC.Source(dsn, "select * from test1")
sqlite = SQLite.Sink(source, db, "test1")
Data.stream!(source, sqlite)

data = SQLite.query(db, "select * from test1")
@test

# test exporting test2 to SQLite
source = ODBC.Source(dsn, "select * from test2")
sqlite = SQLite.Sink(db, "test2")
Data.stream!(source, sqlite)

data = SQLite.query(db, "select * from test2")
@test

ODBC.Source(dsn, "drop table if exists test1")
# ODBC.Source(dsn, "drop table if exists test2")
