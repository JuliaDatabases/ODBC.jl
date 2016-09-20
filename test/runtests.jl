using Base.Test, ODBC, DataStreams, DataFrames, WeakRefStrings, CSV, SQLite, Feather

@show ODBC.listdrivers()
@show ODBC.listdsns()

@show ODBC.API.odbc_dm

@show run(`odbcinst -q -d`)

conn_string = "Driver={MySQL ODBC Driver};SERVER=127.0.0.1;Port=3306;Database=mysql;USER=root;PASSWORD=;Option=3"

run(`uname -a`)
run(`mysqlshow -uroot`)

dsn = ODBC.DSN(conn_string)

# Check some basic queries
dbs = ODBC.query(dsn, "show databases")
ODBC.query(dsn, "use mysql")
data = ODBC.query(dsn, "select table_name from information_schema.tables")

# setup a test database
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
data = Data.stream!(source, DataFrame)
@test size(data) == (1,27)
@test Data.types(data) == map(x->Nullable{x},
[Int64,
 Int8,
 is_windows() ? Float64 : DecFP.Dec64,
 Int32,
 is_windows() ? Float64 : DecFP.Dec64,
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
 WeakRefString{UInt16},
 WeakRefString{UInt16},
 Array{UInt8,1},
 Array{UInt8,1},
 Array{UInt8,1},
 Array{UInt8,1},
 Array{UInt8,1},
 Array{UInt8,1},
 String,
 String,
 String,
 String])
@test data.columns[1][1] === Nullable(Int64(1))
@test data.columns[2][1] === Nullable(Int8(1))
@test data.columns[3][1] === Nullable(is_windows() ? 1.0 : ODBC.DecFP.Dec64(1))
@test data.columns[4][1] === Nullable(Int32(1))
@test data.columns[5][1] === Nullable(is_windows() ? 1.0 : ODBC.DecFP.Dec64(1))
@test data.columns[6][1] === Nullable(Int16(1))
@test data.columns[7][1] === Nullable(Int32(1))
@test data.columns[8][1] === Nullable(Int8(1))
@test data.columns[9][1] === Nullable(Float32(1.2))
@test data.columns[10][1] === Nullable(Float64(1.2))
@test data.columns[11][1] === Nullable(ODBC.API.SQLDate(2016,1,1))
@test data.columns[12][1] === Nullable(ODBC.API.SQLTimestamp(2016,1,1,1,1,1,0))
@test data.columns[13][1] === Nullable(ODBC.API.SQLTimestamp(2016,1,1,1,1,1,0))
@test data.columns[14][1] === Nullable(ODBC.API.SQLTime(1,1,1))
@test data.columns[15][1] === Nullable(Int16(2016))
@test string(get(data.columns[16][1])) == "A"
@test string(get(data.columns[17][1])) == "hey there sailor"
@test get(data.columns[18][1]) == UInt8[0x31,0x32]
@test isnull(data.columns[19][1])
@test get(data.columns[20][1]) == UInt8[0x68,0x65,0x79,0x20,0x74,0x68,0x65,0x72,0x65,0x20,0x61,0x62,0x72,0x61,0x68,0x61,0x6d]
@test get(data.columns[21][1]) == UInt8[0x68,0x65,0x79,0x20,0x74,0x68,0x65,0x72,0x65,0x20,0x62,0x69,0x6c,0x6c]
@test get(data.columns[22][1]) == UInt8[0x68,0x65,0x79,0x20,0x74,0x68,0x65,0x72,0x65,0x20,0x63,0x68,0x61,0x72,0x6c,0x69,0x65]
@test get(data.columns[23][1]) == UInt8[0x68,0x65,0x79,0x20,0x74,0x68,0x65,0x72,0x65,0x20,0x64,0x61,0x6e]
@test string(get(data.columns[24][1])) == "hey there ephraim"
@test string(get(data.columns[25][1])) == "hey there frank"
@test string(get(data.columns[26][1])) == "hey there george"
@test string(get(data.columns[27][1])) == "hey there hank"

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
@test size(data) == (2,27)

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
ODBC.execute!(dsn, "load data local infile '$randoms' into table test2
                    fields terminated by ',' lines terminated by '\n'
                    (id,first_name,last_name,salary,`hourly rate`,hiredate,`last clockin`)")

data = ODBC.query(dsn, "select count(*) from test2")
@test size(data) == (1,1)
@test data.columns[1][1] === Nullable(70000)

df = ODBC.query(dsn, "select * from test2")
@test size(df) == (70000,7)
@test df.columns[1].values == [1:70000...]
@test df.columns[end][1] === Nullable(ODBC.API.SQLTimestamp(2002,1,17,21,32,0,0))

# test exporting test1 to CSV
source = ODBC.Source(dsn, "select * from test1")
csv = CSV.Sink("test1.csv")
Data.stream!(source, csv)
open("test1.csv") do f
    @test readline(f) == "\"test_bigint\",\"test_bit\",\"test_decimal\",\"test_int\",\"test_numeric\",\"test_smallint\",\"test_mediumint\",\"test_tiny_int\",\"test_float\",\"test_real\",\"test_date\",\"test_datetime\",\"test_timestamp\",\"test_time\",\"test_year\",\"test_char\",\"test_varchar\",\"test_binary\",\"test_varbinary\",\"test_tinyblob\",\"test_blob\",\"test_mediumblob\",\"test_longblob\",\"test_tinytext\",\"test_text\",\"test_mediumtext\",\"test_longtext\"\n"
    @test readline(f) == "1,1,+1E+0,1,+1E+0,1,1,1,1.2,1.2,2016-01-01,2016-01-01T01:01:01,2016-01-01T01:01:01,01:01:01,2016,\"A\",\"hey there sailor\",UInt8[0x31,0x32],\"\",UInt8[0x68,0x65,0x79,0x20,0x74,0x68,0x65,0x72,0x65,0x20,0x61,0x62,0x72,0x61,0x68,0x61,0x6d],UInt8[0x68,0x65,0x79,0x20,0x74,0x68,0x65,0x72,0x65,0x20,0x62,0x69,0x6c,0x6c],UInt8[0x68,0x65,0x79,0x20,0x74,0x68,0x65,0x72,0x65,0x20,0x63,0x68,0x61,0x72,0x6c,0x69,0x65],UInt8[0x68,0x65,0x79,0x20,0x74,0x68,0x65,0x72,0x65,0x20,0x64,0x61,0x6e],\"hey there ephraim\",\"hey there frank\",\"hey there george\",\"hey there hank\"\n"
end
rm("test1.csv")

# test exporting test2 to CSV
source = ODBC.Source(dsn, "select * from test2")
csv = CSV.Sink("test2.csv")
Data.stream!(source, csv)
open("test2.csv") do f
    @test readline(f) == "\"ID\",\"first_name\",\"last_name\",\"Salary\",\"hourly rate\",\"hireDate\",\"last clockin\"\n"
    @test readline(f) == "1,\"Lawrence\",\"Powell\",+87217E+0,26.47,2002-04-09,2002-01-17T21:32:00\n"
end

# test exporting test1 to SQLite
db = SQLite.DB()
source = ODBC.Source(dsn, "select * from test1")
SQLite.load(db, "test1", source)

data = SQLite.query(db, "select * from test1")
@test size(data) == (2,27)
@test data.columns[1][1] === Nullable(1)
@test data.columns[3][1] === Nullable(1.0)
@test data.columns[11][1] === Nullable(ODBC.API.SQLDate(2016,1,1))

# test exporting test2 to SQLite
source = ODBC.Source(dsn, "select * from test2")
SQLite.load(db, "test2", source)

data = SQLite.query(db, "select * from test2")
@test size(data) == (70000,7)
@test data.columns[1].values == [1:70000...]
@test data.columns[end][1] === Nullable(ODBC.API.SQLTimestamp(2002,1,17,21,32,0,0))

# test exporting test2 to Feather
file = "test2.feather"
Feather.write(file, ODBC.Source, dsn, "select ID, first_name, last_name, salary + 0E0 as salary, `hourly rate` from test2")
df = Feather.read(file)
@test size(df, 1) == size(data, 1)
@test df.columns[1] == [1:70000...]

ODBC.execute!(dsn, "create table test3 as select * from test2 limit 0")
ODBC.execute!(dsn, "delete from test3")
ODBC.query(dsn, "select * from test2 limit 100", ODBC.Sink, dsn, "test3")

df = ODBC.query(dsn, "select * from test3")
@test size(df) == (100,7)
@test df.columns[1].values == [1:100...]

ODBC.load(dsn, "test3", df; append=true)
df = ODBC.query(dsn, "select * from test3")
@test size(df) == (200,7)
@test df.columns[1].values == append!([1:100...], [1:100...])

stmt = ODBC.prepare(dsn, "insert into test3 values(?,?,?,?,?,?,?)")
ODBC.execute!(stmt, [101, "Steve", "McQueen", 1.0, 100.0, Date(2016,1,1), DateTime(2016,1,1)])

ODBC.execute!(stmt, [102, "Dean", "Martin", 1.5, 10.1, Date(2016,1,2), DateTime(2016,1,2)])

df = ODBC.query(dsn, "select * from test3")
@test size(df) == (202,7)
@test get(df.columns[1][end-1]) == 101
@test get(df.columns[1][end]) == 102
@test get(df.columns[2][end-1]) == "Steve"
@test get(df.columns[2][end]) == "Dean"
@test get(df.columns[3][end-1]) == "McQueen"
@test get(df.columns[3][end]) == "Martin"
@test get(df.columns[4][end-1]) == (is_windows() ? 1.0 : DecFP.Dec64(1))
@test get(df.columns[4][end]) == (is_windows() ? 2.0 : DecFP.Dec64(2))
@test get(df.columns[5][end-1]) == 100.0
@test get(df.columns[5][end]) == 10.1
@test get(df.columns[6][end-1]) == ODBC.API.SQLDate(2016,1,1)
@test get(df.columns[6][end]) == ODBC.API.SQLDate(2016,1,2)
@test get(df.columns[7][end-1]) == ODBC.API.SQLTimestamp(2016,1,1,0,0,0,0)
@test get(df.columns[7][end]) == ODBC.API.SQLTimestamp(2016,1,2,0,0,0,0)

ODBC.execute!(dsn, "drop table if exists test1")
ODBC.Source(dsn, "drop table if exists test2")
ODBC.Source(dsn, "drop table if exists test3")
rm("test2.csv")

# more robust Feather testing
mysqltypes = Dict(Int32=>"INT", Float64=>"DOUBLE", CategoricalArrays.NominalValue{String,Int32}=>"VARCHAR(255)", CategoricalArrays.OrdinalValue{String,Int32}=>"VARCHAR(255)", WeakRefString{UInt8}=>"VARCHAR(255)")
columndef(name, typ) = "`$name` $(mysqltypes[typ <: Nullable ? eltype(typ) : typ]),"

testnull{T1, T2}(v1::T1, v2::T2) = v1 == v2
testnull{T1, T2}(v1::Nullable{T1}, v2::Nullable{T2}) = (isnull(v1) && isnull(v2)) || (!isnull(v1) && !isnull(v2) && get(v1) == get(v2))
testnull{T1, T2}(v1::T1, v2::Nullable{T2}) = !isnull(v2) && get(v2) == v1
testnull{T1, T2}(v1::Nullable{T1}, v2::T2) = !isnull(v1) && get(v1) == v2

feather_dir = joinpath(dirname(@__FILE__), "../../Feather/test/data")
# feather_dir = "/Users/jacobquinn/.julia/v0.5/Feather/test/data"
# files = readdir(feather_dir)
for file in readdir(feather_dir)
    source = Feather.Source(joinpath(feather_dir,file))
    nms = Data.header(source)
    typs = Data.types(source)
    columndefs = ""
    for i = 1:length(nms)
        columndefs *= columndef(nms[i], typs[i])
    end
    createtable = "CREATE TABLE feather_test ($(chop(columndefs)))"
    ODBC.execute!(dsn, createtable)
    ODBC.load(dsn, "feather_test", source)
    df = ODBC.query(dsn, "select * from feather_test")
    df2 = Feather.read(source)
    # tests
    for (c1,c2) in zip(df.columns,df2.columns)
        for i = 1:length(c1)
            @test testnull(c1[i], c2[i])
        end
    end
    ODBC.execute!(dsn, "drop table feather_test")
end

ODBC.disconnect!(dsn)
