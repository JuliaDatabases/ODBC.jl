@testset "mssql" begin

    # Microsoft drivers (mssql) don't support reading usernames and passwords from .odbc.ini
    # files so you have to specify those explicitly in the DSN setup call:
    # dsn = ODBC.DSN("MSSQL-test", "yourusername", "yourpassword")
    dsn = ODBC.DSN("MSSQL-test", "SA", "YourStrong!Passw0rd")

    @testset "basic queries" begin
        dbs = ODBC.query(dsn, "select name from sys.databases")
        data = ODBC.query(dsn, "select table_name from master.information_schema.tables")
        data = ODBC.query(dsn, "select table_name from tempdb.information_schema.tables")
        data = ODBC.query(dsn, "select table_name from model.information_schema.tables")
        data = ODBC.query(dsn, "select table_name from msdb.information_schema.tables")
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
                             test_money money,
                             test_numeric numeric,
                             test_smallint smallint,
                             test_smallmoney smallmoney,
                             test_tiny_int tinyint,
                             test_float float,
                             test_real real,
                             test_date date,
                             test_datetime2 datetime2,
                             test_datetime datetime,
                             test_datetimeoffset datetimeoffset,
                             test_smalldatetime smalldatetime,
                             test_time time,
                             test_char char(1),
                             test_varchar varchar(16),
                             test_nchar nchar(1),
                             test_nvarchar nvarchar(16),
                             test_binary binary(2),
                             test_varbinary varbinary(16)
                            )")
        data = ODBC.query(dsn, "select * from information_schema.columns where table_name = 'test1'")
        ODBC.execute!(dsn, "insert test1 VALUES
                            (1, -- bigint
                             1, -- bit
                             1.0, -- decimal
                             1, -- int
                             1.0, -- money
                             1.0, -- numeric
                             1, -- smallint
                             1.0, -- smallmoney
                             1, -- tinyint
                             1.2, -- float
                             1.2, -- real
                             '2016-01-01', -- date
                             '2016-01-01 01:01:01', -- datetime2
                             '2016-01-01 01:01:01', -- datetime
                             '2016-01-01 01:01:01-05:00', -- datetimeoffset
                             '2016-01-01 01:01:01', -- smalldatetime
                             '01:01:01', -- time
                             'A', -- char(1)
                             'hey there sailor', -- varchar
                             'B', -- nchar(1)
                             'hey there sally', -- nvarchar
                             cast(123456 as binary(2)), -- binary
                             cast(123456 as varbinary(16)) -- varbinary
                            )")
        data = ODBC.query(dsn, "select * from test1")

        @test size(data) == (1,23)
        @test Tables.schema(data).types == (
            Union{Int64, Missing},
            Union{Int8, Missing},
            Union{DecFP.Dec64, Missing},
            Union{Int32, Missing},
            Union{DecFP.Dec64, Missing},
            Union{DecFP.Dec64, Missing},
            Union{Int16, Missing},
            Union{DecFP.Dec64, Missing},
            Union{Int8, Missing},
            Union{Float64, Missing},
            Union{Float32, Missing},
            Union{ODBC.API.SQLDate, Missing},
            Union{ODBC.API.SQLTimestamp, Missing},
            Union{ODBC.API.SQLTimestamp, Missing},
            Union{ODBC.API.SQLTimestamp, Missing},
            Union{ODBC.API.SQLTimestamp, Missing},
            Union{ODBC.API.SQLTime, Missing},
            Union{String, Missing},
            Union{String, Missing},
            Union{String, Missing},
            Union{String, Missing},
            Union{Array{UInt8,1}, Missing},
            Union{Array{UInt8,1}, Missing},
        )

        @test data[1][1] === Int64(1)
        @test data[2][1] === Int8(1)
        @test data[3][1] === DecFP.Dec64(1)
        @test data[4][1] === Int32(1)
        @test data[5][1] == DecFP.Dec64(1)
        @test data[6][1] === DecFP.Dec64(1)
        @test data[7][1] === Int16(1)
        @test data[8][1] == DecFP.Dec64(1)
        @test data[9][1] === Int8(1)
        @test data[10][1] === Float64(1.2)
        @test data[11][1] === Float32(1.2)
        @test data[12][1] === ODBC.API.SQLDate(2016,1,1)
        @test data[13][1] === ODBC.API.SQLTimestamp(2016,1,1,1,1,1,0)
        @test data[14][1] === ODBC.API.SQLTimestamp(2016,1,1,1,1,1,0)
        @test_broken data[15][1] === ODBC.API.SQLTimestamp(2016,1,1,6,1,1,0)
        @test data[16][1] === ODBC.API.SQLTimestamp(2016,1,1,1,1,0,0)
        @test data[17][1] === ODBC.API.SQLTime(1,1,1)
        @test data[18][1] == "A"
        @test data[19][1] == "hey there sailor"
        @test data[20][1] == "B"
        @test data[21][1] == "hey there sally"
        @test data[22][1] == UInt8[0xe2, 0x40]
        @test data[23][1] == UInt8[0x00, 0x01, 0xe2, 0x40]

        ODBC.execute!(dsn, "insert test1 VALUES
                            (2, -- bigint
                             1, -- bit
                             2.0, -- decimal
                             2, -- int
                             2.0, -- money
                             2.0, -- numeric
                             2, -- smallint
                             2.0, -- smallmoney
                             2, -- tinyint
                             2.2, -- float
                             2.2, -- real
                             '2016-01-01', -- date
                             '2016-01-01 01:01:01', -- datetime2
                             '2016-01-01 01:01:01', -- datetime
                             '2016-01-01 01:01:01-05:00', -- datetimeoffset
                             '2016-01-01 01:01:01', -- smalldatetime
                             '01:01:01', -- time
                             'A', -- char(1)
                             'hey there sailor', -- varchar
                             'B', -- nchar(1)
                             'hey there sally', -- nvarchar
                             cast(123456 as binary(2)), -- binary
                             cast(123456 as varbinary(16)) -- varbinary
                            )")
        data = ODBC.query(dsn, "select * from test1")
        @test size(data) == (2,23)
        @test data[1][1] === Int64(1)
        @test data[1][2] === Int64(2)

        # @testset "Streaming mssql data to CSV" begin
        #     # Test exporting test1 to CSV
        #     temp_filename = "mssql_test1.csv"
        #     source = ODBC.Query(dsn, "select * from test1")
        #     CSV.write(temp_filename, source)

        #     open(temp_filename) do f
        #         @test readline(f) == (
        #             "test_bigint,test_bit,test_decimal,test_int,test_money,test_numeric," *
        #             "test_smallint,test_smallmoney,test_tiny_int,test_float,test_real," *
        #             "test_date,test_datetime2,test_datetime,test_datetimeoffset," *
        #             "test_smalldatetime,test_time,test_char,test_varchar,test_nchar," *
        #             "test_nvarchar,test_binary,test_varbinary"
        #         )
        #         @test readline(f) == (
        #             "1,1,1.0,1,1.0,1.0,1,1.0,1,1.2,1.2,2016-01-01,2016-01-01T01:01:01," *
        #             "2016-01-01T01:01:01,2016-01-01T00:01:01,2016-01-01T01:01:00," *
        #             "01:01:01,A,hey there sailor,B,hey there sally,\"UInt8[0xe2, 0x40]\"," *
        #             "\"UInt8[0x00, 0x01, 0xe2, 0x40]\""
        #         )
        #         @test readline(f) == (
        #             "2,1,2.0,2,2.0,2.0,2,2.0,2,2.2,2.2,2016-01-01,2016-01-01T01:01:01," *
        #             "2016-01-01T01:01:01,2016-01-01T00:01:01,2016-01-01T01:01:00," *
        #             "01:01:01,A,hey there sailor,B,hey there sally,\"UInt8[0xe2, 0x40]\"," *
        #             "\"UInt8[0x00, 0x01, 0xe2, 0x40]\""
        #         )
        #     end
        #     rm(temp_filename)
        # end

        @testset "Exporting mssql data to SQLite" begin
            # Test exporting test1 to SQLite
            db = SQLite.DB()
            source = ODBC.Query(dsn, "select * from test1")
            SQLite.load!(source, db, "mssql_test1")

            data = SQLite.Query(db, "select * from mssql_test1") |> DataFrame
            @test size(data) == (2,23)
            @test data[1][1] === 1
            @test data[10][1] === 1.2
            @test data[12][1] === ODBC.API.SQLDate(2016,1,1)
            @test data[23][1] == UInt8[0x00, 0x01, 0xe2, 0x40]
        end

        ODBC.execute!(dsn, "drop table if exists test1")
    end

    @testset "employee" begin
        ODBC.execute!(dsn, "drop table if exists employee")

        ODBC.execute!(dsn, """
        CREATE TABLE Employee
        (
            ID INT NOT NULL IDENTITY(1,1) PRIMARY KEY,
            Name VARCHAR(255),
            Salary FLOAT,
            JoinDate DATE,
            LastLogin DATETIME,
            LunchTime TIME,
            OfficeNo TINYINT,
            Senior BIT,
            empno SMALLINT
        );""")
        ODBC.execute!(dsn, """
        INSERT INTO Employee
        (Name, Salary, JoinDate, LastLogin, LunchTime, OfficeNo, Senior, empno)
         VALUES ('John', 10000.50, '2015-8-3', '2015-9-5 12:31:30', '12:00:00', 1, 1, 1301),
         ('Tom', 20000.25, '2015-8-4', '2015-10-12 13:12:14', '13:00:00', 12, 1, 1422),
         ('Jim', 30000.00, '2015-6-2', '2015-9-5 10:05:10', '12:30:00', 45, 0, 1567),
         ('Tim', 15000.50, '2015-7-25', '2015-10-10 12:12:25', '12:30:00', 56, 1, 3200);
        """)
        data = ODBC.query(dsn, "select * from employee")
        @test size(data) == (4,9)
        ODBC.execute!(dsn, "drop table if exists employee")
    end

    ODBC.disconnect!(dsn)
end
