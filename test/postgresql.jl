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
        @test Data.types(Data.schema(data)) == (
          Union{Int64, Missing}
         ,Union{DecFP.Dec64, Missing}
         ,Union{Int32, Missing}
         ,Union{DecFP.Dec64, Missing}
         ,Union{Int16, Missing}
         ,Union{Float32, Missing}
         ,Union{Float64, Missing}
         ,Union{Float64, Missing}
         ,Union{ODBC.API.SQLDate, Missing}
         ,Union{ODBC.API.SQLTimestamp, Missing}
         ,Union{ODBC.API.SQLTime, Missing}
         ,Union{WeakRefStrings.WeakRefString{UInt8}, Missing}
         ,Union{WeakRefStrings.WeakRefString{UInt8}, Missing}
         ,Union{Array{UInt8,1}, Missing}
         ,Union{WeakRefStrings.WeakRefString{UInt8}, Missing}
         ,Union{String, Missing}
         ,Union{WeakRefStrings.WeakRefString{UInt8}, Missing})
        showall(data)
        ODBC.execute!(dsn, "drop table if exists test1")
    end

    ODBC.disconnect!(dsn)
end
