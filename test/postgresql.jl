@testset "postgresql" begin
    dsn = ODBC.DSN("PgSQL-test")

    @testset "basic queries" begin
        dbs = ODBC.query(dsn, "SELECT datname FROM pg_database WHERE datistemplate = false;")
        data = ODBC.query(dsn, "SELECT table_schema, table_name FROM information_schema.tables ORDER BY table_schema,table_name;")
    end

    @testset "test1" begin
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
        data = ODBC.query(dsn, "select * from information_schema.tables where table_name = 'test1'")
        println("Postgres table 'test1' schema:")
        println()
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
                             'hey there abraham', -- text,
                             ARRAY[1, 2, 3] -- integer array
                            )")
        data = ODBC.query(dsn, "select * from test1")
        @test size(data) == (1,17)
        @test Tables.schema(data).types == (
            Union{Int64, Missing},
            Union{DecFP.Dec64, Missing},
            Union{Int32, Missing},
            Union{DecFP.Dec64, Missing},
            Union{Int16, Missing},
            Union{Float32, Missing},
            Union{Float64, Missing},
            Union{Float64, Missing},
            Union{ODBC.API.SQLDate, Missing},
            Union{ODBC.API.SQLTimestamp, Missing},
            Union{ODBC.API.SQLTime, Missing},
            Union{String, Missing},
            Union{String, Missing},
            Union{Array{UInt8,1}, Missing},
            Union{String, Missing},
            Union{String, Missing},
            Union{String, Missing},
        )
        println("Postgres table 'test1':")
        show(data)
        println()

        @testset "Streaming postgres data to CSV" begin
            # Test exporting test1 to CSV
            temp_filename = "postgres_test1.csv"
            source = ODBC.Query(dsn, "select * from test1")
            CSV.write(temp_filename, source)

            open(temp_filename) do f
                @test readline(f) == (
                    "test_bigint,test_decimal,test_int,test_numeric,test_smallint," *
                    "test_float,test_real,test_money,test_date,test_timestamp,test_time," *
                    "test_char,test_varchar,test_bytea,test_boolean,test_text,test_array"
                )
                @test readline(f) == (
                    "1,1.2,2,1.4,3,1.6,1.8,2.0,2016-01-01,2016-01-01T01:01:01,01:01:01," *
                    "A,hey there sailor,,1,hey there abraham,\"{1,2,3}\""
                )
            end
            rm(temp_filename)
        end

        @testset "Exporting postgres data to SQLite" begin
            # Test exporting test1 to SQLite
            db = SQLite.DB()
            source = ODBC.Query(dsn, "select * from test1")
            SQLite.load!(source, db, "postgres_test1")

            data = SQLite.query(db, "select * from postgres_test1")
            @test size(data) == (1,17)
            @test data[1][1] === 1
            @test data[2][1] === 1.2
            @test data[9][1] === ODBC.API.SQLDate(2016,1,1)
            @test data[17][1] == "{1,2,3}"
        end

        ODBC.execute!(dsn, "drop table if exists test1")
    end

    ODBC.disconnect!(dsn)
end
