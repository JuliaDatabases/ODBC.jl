@testset "mysql" begin
    # Some mysql drivers don't support reading usernames and passwords from .odbc.ini
    # files so you have to specify those explicitly in the DSN setup call:
    # dsn = ODBC.DSN("MySQL-test", "root", "")
    dsn = ODBC.DSN("MySQL-test")

    @testset "basic queries" begin
        dbs = ODBC.query(dsn, "show databases")
        ODBC.query(dsn, "use mysql")
        data = ODBC.query(dsn, "select table_name from information_schema.tables")
    end

    @testset "create testdb" begin
        ODBC.execute!(dsn, "drop database if exists testdb")
        ODBC.execute!(dsn, "create database testdb")
        ODBC.execute!(dsn, "use testdb")
    end

    @testset "test1" begin
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
        data = ODBC.Query(dsn, "select * from information_schema.columns where table_name = 'test1'")
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

        @test size(data) == (1,27)
        @test Tables.schema(data).types == (
            Union{Int64, Missing},
            Union{Int8, Missing},
            Union{DecFP.Dec64, Missing},
            Union{Int32, Missing},
            Union{DecFP.Dec64, Missing},
            Union{Int16, Missing},
            Union{Int32, Missing},
            Union{Int8, Missing},
            Union{Float32, Missing},
            Union{Float64, Missing},
            Union{ODBC.API.SQLDate, Missing},
            Union{ODBC.API.SQLTimestamp, Missing},
            Union{ODBC.API.SQLTimestamp, Missing},
            Union{ODBC.API.SQLTime, Missing},
            Union{Int16, Missing},
            Union{String, Missing},
            Union{String, Missing},
            Union{Array{UInt8,1}, Missing},
            Union{Array{UInt8,1}, Missing},
            Union{Array{UInt8,1}, Missing},
            Union{Array{UInt8,1}, Missing},
            Union{Array{UInt8,1}, Missing},
            Union{Array{UInt8,1}, Missing},
            Union{String, Missing},
            Union{String, Missing},
            Union{String, Missing},
            Union{String, Missing}
        )
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
        @test ismissing(data[19][1])
        @test data[20][1] == UInt8[0x68,0x65,0x79,0x20,0x74,0x68,0x65,0x72,0x65,0x20,0x61,0x62,0x72,0x61,0x68,0x61,0x6d]
        @test data[21][1] == UInt8[0x68,0x65,0x79,0x20,0x74,0x68,0x65,0x72,0x65,0x20,0x62,0x69,0x6c,0x6c]
        @test data[22][1] == UInt8[0x68,0x65,0x79,0x20,0x74,0x68,0x65,0x72,0x65,0x20,0x63,0x68,0x61,0x72,0x6c,0x69,0x65]
        @test data[23][1] == UInt8[0x68,0x65,0x79,0x20,0x74,0x68,0x65,0x72,0x65,0x20,0x64,0x61,0x6e]
        @test string(data[24][1]) == "hey there ephraim"
        @test string(data[25][1]) == "hey there frank"
        @test string(data[26][1]) == "hey there george"
        @test string(data[27][1]) == "hey there hank"

        ODBC.execute!(dsn, "insert test1 VALUES
                            (2, -- bigint
                             1, -- bit
                             2.0, -- decimal
                             2, -- int
                             2.0, -- numeric
                             2, -- smallint
                             2, -- mediumint
                             2, -- tinyint
                             2.2, -- float
                             2.2, -- double
                             '2016-01-01', -- date
                             '2016-01-01 01:01:01', -- datetime
                             '2016-01-01 01:01:01', -- timestamp
                             '01:01:01', -- time
                             2016, -- year
                             'B', -- char(1)
                             'hey there sailor', -- varchar
                             cast('12' as binary(2)), -- binary
                             NULL, -- varbinary
                             'hey there abraham2', -- tinyblob
                             'hey there bill2', -- blob
                             'hey there charlie2', -- mediumblob
                             'hey there dan2', -- longblob
                             'hey there ephraim2', -- tinytext
                             'hey there frank2', -- text
                             'hey there george2', -- mediumtext
                             'hey there hank2' -- longtext
                            )")
        data = ODBC.query(dsn, "select * from test1")
        @test size(data) == (2,27)
        @test data[1][1] === Int64(1)
        @test data[1][2] === Int64(2)

        @testset "Streaming mysql data to CSV" begin
            # Test exporting test1 to CSV
            temp_filename = "mysql_test1.csv"
            source = ODBC.Query(dsn, "select * from test1")
            CSV.write(temp_filename, source)
            
            open(temp_filename) do f
                @test readline(f) == (
                    "test_bigint,test_bit,test_decimal,test_int,test_numeric," *
                    "test_smallint,test_mediumint,test_tiny_int,test_float,test_real," *
                    "test_date,test_datetime,test_timestamp,test_time,test_year," *
                    "test_char,test_varchar,test_binary,test_varbinary,test_tinyblob," *
                    "test_blob,test_mediumblob,test_longblob,test_tinytext,test_text," *
                    "test_mediumtext,test_longtext"
                )
                @test readline(f) == (
                    "1,1,1.0,1,1.0,1,1,1,1.2,1.2,2016-01-01,2016-01-01T01:01:01,2016-01-01T01:01:01,01:01:01,2016,A,hey there sailor,\"UInt8[0x31, 0x32]\",,\"UInt8[0x68, 0x65, 0x79, 0x20, 0x74, 0x68, 0x65, 0x72, 0x65, 0x20, 0x61, 0x62, 0x72, 0x61, 0x68, 0x61, 0x6d]\",\"UInt8[0x68, 0x65, 0x79, 0x20, 0x74, 0x68, 0x65, 0x72, 0x65, 0x20, 0x62, 0x69, 0x6c, 0x6c]\",\"UInt8[0x68, 0x65, 0x79, 0x20, 0x74, 0x68, 0x65, 0x72, 0x65, 0x20, 0x63, 0x68, 0x61, 0x72, 0x6c, 0x69, 0x65]\",\"UInt8[0x68, 0x65, 0x79, 0x20, 0x74, 0x68, 0x65, 0x72, 0x65, 0x20, 0x64, 0x61, 0x6e]\",hey there ephraim,hey there frank,hey there george,hey there hank"
                )
                @test readline(f) == (
                    "2,1,2.0,2,2.0,2,2,2,2.2,2.2,2016-01-01,2016-01-01T01:01:01,2016-01-01T01:01:01,01:01:01,2016,B,hey there sailor,\"UInt8[0x31, 0x32]\",,\"UInt8[0x68, 0x65, 0x79, 0x20, 0x74, 0x68, 0x65, 0x72, 0x65, 0x20, 0x61, 0x62, 0x72, 0x61, 0x68, 0x61, 0x6d, 0x32]\",\"UInt8[0x68, 0x65, 0x79, 0x20, 0x74, 0x68, 0x65, 0x72, 0x65, 0x20, 0x62, 0x69, 0x6c, 0x6c, 0x32]\",\"UInt8[0x68, 0x65, 0x79, 0x20, 0x74, 0x68, 0x65, 0x72, 0x65, 0x20, 0x63, 0x68, 0x61, 0x72, 0x6c, 0x69, 0x65, 0x32]\",\"UInt8[0x68, 0x65, 0x79, 0x20, 0x74, 0x68, 0x65, 0x72, 0x65, 0x20, 0x64, 0x61, 0x6e, 0x32]\",hey there ephraim2,hey there frank2,hey there george2,hey there hank2"
                )
            end
            rm(temp_filename)
        end

        @testset "Exporting mysql data to SQLite" begin
            # Test exporting test1 to SQLite
            db = SQLite.DB()
            source = ODBC.Query(dsn, "select * from test1")
            SQLite.load!(source, db, "mysql_test1")

            data = SQLite.query(db, "select * from mysql_test1")
            @test size(data) == (2,27)
            @test data[1][1] === 1
            @test data[10][1] === 1.2
            @test data[11][1] === ODBC.API.SQLDate(2016,1,1)
            @test data[27][1] == "hey there hank"
        end

        ODBC.execute!(dsn, "drop table if exists test1")
    end

    @testset "large query" begin
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
        randoms = joinpath(dirname(pathof(ODBC)), "../test/data/randoms.csv")
        ODBC.execute!(dsn, "load data local infile '$randoms' into table test2
                            fields terminated by ',' lines terminated by '\n'
                            (id,first_name,last_name,salary,`hourly rate`,hiredate,`last clockin`)")

        data = ODBC.query(dsn, "select count(*) from test2")
        @test size(data) == (1,1)
        @test data[1][1] === 70000

        df = ODBC.query(dsn, "select * from test2")
        @test size(df) == (70000,7)
        @test df[1] == collect(1:70000)
        @test df[end][1] === ODBC.API.SQLTimestamp(2002,1,17,21,32,0,0)
    end

    @testset "prepared statement" begin
        ODBC.execute!(dsn, "create table test3 as select * from test2 limit 0")
        ODBC.execute!(dsn, "delete from test3")

        stmt = ODBC.prepare(dsn, "insert into test3 values(?,?,?,?,?,?,?)")
        ODBC.execute!(stmt, [101, "Steve", "McQueen", 1.0, 100.0, Date(2016,1,1), DateTime(2016,1,1)])

        ODBC.execute!(stmt, [102, "Dean", "Martin", 1.5, 10.1, Date(2016,1,2), DateTime(2016,1,2)])

        df = ODBC.query(dsn, "select * from test3")
        @test size(df) == (2,7)
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
        ODBC.execute!(dsn, "drop table if exists test2")
        ODBC.execute!(dsn, "drop table if exists test3")
    end

    ODBC.disconnect!(dsn)
end
