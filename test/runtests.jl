using Base.Test, ODBC, DataStreams, Nulls, WeakRefStrings, DataFrames

@show ODBC.drivers()
@show ODBC.dsns()

@show ODBC.API.odbc_dm

@show run(`odbcinst -q -d`)

run(`uname -a`)

props = open(f->Dict(split(ln, ':') for ln in eachline(f)) , "/Users/jacobquinn/.tug/application.properties")
RIG, server, port = map(strip, split(props["environment.subdomain"], '.'))[1], strip(props["routing.services.mysql.host"]), strip(props["routing.services.mysql.port"])
dsn = ODBC.DSN("Driver={MySQL ODBC Driver}; user=domo; password=popchart; server=$server; port=$port;")

# dsn = ODBC.DSN("Driver=MySQL;uid=root")
# dsn = ODBC.DSN("MySQL-test", "root", "")

# Check some basic queries
dbs = ODBC.query(dsn, "show databases")
ODBC.query(dsn, "use mysql")
data = ODBC.query(dsn, "select table_name from information_schema.tables")

# setup a test database
println("testing all mysql types...")
ODBC.execute!(dsn, "drop database if exists testdb")
ODBC.execute!(dsn, "create database testdb")
ODBC.execute!(dsn, "use testdb")
ODBC.execute!(dsn, "drop table if exists test1")
ODBC.execute!(dsn, "create table test1
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
ODBC.execute!(dsn, "insert test1 VALUES
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
                     '2016-01-01 01:01:01', -- timestamp
                     '01:01:01', -- time
                     2016, -- year
                     'A', -- char(1)
                     'hey there sailor', -- varchar
                     cast('12' as binary(2)), -- binary
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

data = ODBC.query(source)
@test size(Data.schema(data)) == (1,27)
@test Data.types(Data.schema(data)) == (
 Union{Int64, Null},
 Union{Int8, Null},
 Union{DecFP.Dec64, Null},
 Union{Int32, Null},
 Union{DecFP.Dec64, Null},
 Union{Int16, Null},
 Union{Int32, Null},
 Union{Int8, Null},
 Union{Float32, Null},
 Union{Float64, Null},
 Union{ODBC.API.SQLDate, Null},
 Union{ODBC.API.SQLTimestamp, Null},
 Union{ODBC.API.SQLTimestamp, Null},
 Union{ODBC.API.SQLTime, Null},
 Union{Int16, Null},
 Union{WeakRefString{UInt8}, Null},
 Union{WeakRefString{UInt8}, Null},
 Union{Array{UInt8,1}, Null},
 Union{Array{UInt8,1}, Null},
 Union{Array{UInt8,1}, Null},
 Union{Array{UInt8,1}, Null},
 Union{Array{UInt8,1}, Null},
 Union{Array{UInt8,1}, Null},
 Union{String, Null},
 Union{String, Null},
 Union{String, Null},
 Union{String, Null})
@test data[1][1] === Int64(1)
@test data[2][1] === Int8(1)
@test data[3][1] === DecFP.Dec64(1)
@test data[4][1] === Int32(1)
@test data[5][1] === DecFP.Dec64(1)
@test data[6][1] === Int16(1)
@test data[7][1] === Int32(1)
@test data[8][1] === Int8(1)
@test data[9][1] === Float32(1.2)
@test data[10][1] === Float64(1.2)
@test data[11][1] === ODBC.API.SQLDate(2016,1,1)
@test data[12][1] === ODBC.API.SQLTimestamp(2016,1,1,1,1,1,0)
@test data[13][1] === ODBC.API.SQLTimestamp(2016,1,1,1,1,1,0)
@test data[14][1] === ODBC.API.SQLTime(1,1,1)
@test data[15][1] === Int16(2016)
@test string(data[16][1]) == "A"
@test string(data[17][1]) == "hey there sailor"
@test data[18][1] == UInt8[0x31,0x32]
@test isnull(data[19][1])
@test data[20][1] == UInt8[0x68,0x65,0x79,0x20,0x74,0x68,0x65,0x72,0x65,0x20,0x61,0x62,0x72,0x61,0x68,0x61,0x6d]
@test data[21][1] == UInt8[0x68,0x65,0x79,0x20,0x74,0x68,0x65,0x72,0x65,0x20,0x62,0x69,0x6c,0x6c]
@test data[22][1] == UInt8[0x68,0x65,0x79,0x20,0x74,0x68,0x65,0x72,0x65,0x20,0x63,0x68,0x61,0x72,0x6c,0x69,0x65]
@test data[23][1] == UInt8[0x68,0x65,0x79,0x20,0x74,0x68,0x65,0x72,0x65,0x20,0x64,0x61,0x6e]
@test string(data[24][1]) == "hey there ephraim"
@test string(data[25][1]) == "hey there frank"
@test string(data[26][1]) == "hey there george"
@test string(data[27][1]) == "hey there hank"

ODBC.execute!(dsn, "insert test1 VALUES
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
                     '2016-01-01 01:01:01', -- timestamp
                     '01:01:01', -- time
                     2016, -- year
                     'A', -- char(1)
                     'hey there sailor', -- varchar
                     cast('12' as binary(2)), -- binary
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
@test size(Data.schema(data)) == (2,27)
println("passed. testing large query...")

ODBC.execute!(dsn, "drop table if exists test2")
ODBC.execute!(dsn, """
CREATE TABLE test2
(
    ID INT NOT NULL PRIMARY KEY,
    first_name VARCHAR(25),
    last_name VARCHAR(25),
    Salary DECIMAL,
    `hourly rate` real,
    hireDate DATE,
    `last clockin` DATETIME
);""")
randoms = joinpath(dirname(@__FILE__), "randoms.csv")
# randoms = joinpath(Pkg.dir("ODBC"), "test/randoms.csv")
ODBC.execute!(dsn, "load data local infile '$randoms' into table test2
                    fields terminated by ',' lines terminated by '\n'
                    (id,first_name,last_name,salary,`hourly rate`,hiredate,`last clockin`)")

data = ODBC.query(dsn, "select count(*) from test2")
@test size(Data.schema(data)) == (1,1)
@test data[1][1] === 70000

df = ODBC.query(dsn, "select * from test2")
@test size(Data.schema(df)) == (70000,7)
@test df[1] == collect(1:70000)
@test df[end][1] === ODBC.API.SQLTimestamp(2002,1,17,21,32,0,0)
println("passed. testing prepared statement...")

ODBC.execute!(dsn, "create table test3 as select * from test2 limit 0")
ODBC.execute!(dsn, "delete from test3")

stmt = ODBC.prepare(dsn, "insert into test3 values(?,?,?,?,?,?,?)")
ODBC.execute!(stmt, [101, "Steve", "McQueen", 1.0, 100.0, Date(2016,1,1), DateTime(2016,1,1)])

ODBC.execute!(stmt, [102, "Dean", "Martin", 1.5, 10.1, Date(2016,1,2), DateTime(2016,1,2)])

df = ODBC.query(dsn, "select * from test3")
@test size(Data.schema(df)) == (2,7)
@test df[1][end-1] == 101
@test df[1][end] == 102
@test df[2][end-1] == "Steve"
@test df[2][end] == "Dean"
@test df[3][end-1] == "McQueen"
@test df[3][end] == "Martin"
@test df[4][end-1] == DecFP.Dec64(1)
@test df[4][end] == DecFP.Dec64(2)
@test df[5][end-1] == 100.0
@test df[5][end] == 10.1
@test df[6][end-1] == ODBC.API.SQLDate(2016,1,1)
@test df[6][end] == ODBC.API.SQLDate(2016,1,2)
@test df[7][end-1] == ODBC.API.SQLTimestamp(2016,1,1,0,0,0,0)
@test df[7][end] == ODBC.API.SQLTimestamp(2016,1,2,0,0,0,0)

ODBC.execute!(dsn, "drop table if exists test1")
ODBC.Source(dsn, "drop table if exists test2")
ODBC.Source(dsn, "drop table if exists test3")

ODBC.disconnect!(dsn)
println("mysql passed.")

# PostgreSQL
dsn = ODBC.DSN("PgSQL-test", "postgres", "")
dbs = ODBC.query(dsn, "SELECT datname FROM pg_database WHERE datistemplate = false;")
data = ODBC.query(dsn, "SELECT table_schema,table_name FROM information_schema.tables ORDER BY table_schema,table_name;")
ODBC.execute!(dsn, "drop table if exists test1")
ODBC.execute!(dsn, "create table test1
                    (test_bigint bigint,
                     test_decimal decimal,
                     test_int integer,
                     test_numeric numeric,
                     test_smallint smallint,
                     test_float real,
                     test_real double precision,
                     test_money money,
                     test_date date,
                     test_timestamp timestamp,
                     test_time time,
                     test_char char(1),
                     test_varchar varchar(16),
                     test_bytea bytea,
                     test_boolean boolean,
                     test_text text,
                     test_array integer[]
                    )")
data = ODBC.query(dsn, "select * from information_schema where table_name = 'test1'")
showall(data)
ODBC.execute!(dsn, "insert into test1 VALUES
                    (1, -- bigint,
                     1.2, -- decimal,
                     2, -- integer,
                     1.4, -- numeric,
                     3, -- smallint,
                     1.6, -- real,
                     1.8, -- double precision,
                     2.0, -- money,
                     '2016-01-01', -- date,
                     '2016-01-01 01:01:01', -- timestamp,
                     '01:01:01', -- time,
                     'A', -- char(1),
                     'hey there sailor', -- varchar(16),
                     NULL, -- bytea,
                     TRUE, -- boolean,
                     'hey there abraham', -- text
                     ARRAY[1, 2, 3] -- integer array
                    )")
source = ODBC.Source(dsn, "select * from test1")
data = ODBC.query(source)
@test size(Data.schema(data)) == (1,17)
@test Data.types(data, Data.Field) == (
  Union{Int64, Null}
 ,Union{DecFP.Dec64, Null}
 ,Union{Int32, Null}
 ,Union{DecFP.Dec64, Null}
 ,Union{Int16, Null}
 ,Union{Float32, Null}
 ,Union{Float64, Null}
 ,Union{Float64, Null}
 ,Union{ODBC.API.SQLDate, Null}
 ,Union{ODBC.API.SQLTimestamp, Null}
 ,Union{ODBC.API.SQLTime, Null}
 ,Union{WeakRefStrings.WeakRefString{UInt8}, Null}
 ,Union{WeakRefStrings.WeakRefString{UInt8}, Null}
 ,Union{Array{UInt8,1}, Null}
 ,Union{WeakRefStrings.WeakRefString{UInt8}, Null}
 ,Union{String, Null}
 ,Union{WeakRefStrings.WeakRefString{UInt8}, Null})
@test data.test_array[1] == "{1,2,3}"
showall(data)

println("postgresql passed.")