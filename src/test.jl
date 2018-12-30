
#include("ODBC.jl")
using ODBC;

dsn = ODBC.DSN("mysql_test","pascal","pascal");
ODBC.execute!(dsn, "drop table if exists test1")
ODBC.execute!(dsn, "create table test1 (test_char1 char(10), test_char2 char(10))")
ODBC.execute!(dsn, "insert test1 VALUES ('éééééééééé','aaaaaaaaaa')")
tbl = ODBC.query(dsn, "SELECT * FROM test1;")
ODBC.disconnect!(dsn)





include("ODBC.jl")
#using ODBC;
using Dates

dsn = ODBC.DSN("mysql_test","pascal","pascal");

ODBC.execute!(dsn, "drop table if exists test3")
ODBC.execute!(dsn, """
CREATE TABLE test3
(
    ID INT NOT NULL PRIMARY KEY,
    first_name VARCHAR(10),
    last_name VARCHAR(10),
    Salary DECIMAL,
    `hourly rate` real,
    hireDate DATE,
    `last clockin` DATETIME
);""")



    stmt = ODBC.prepare(dsn, "insert into test3 values(?,?,?,?,?,?,?)")
    ODBC.execute!(stmt, [101, "Steve", "McQueen", 1.0, 100.0, Date(2016,1,1), DateTime(2016,1,1)])

    ODBC.execute!(stmt, [102, "Dean", "Martin", 1.5, 10.1, Date(2016,1,2), DateTime(2016,1,2)])

    ODBC.execute!(stmt, [103, "Père", "Noël", 1.5, 10.1, Date(2016,1,2), DateTime(2016,1,2)])

    df = ODBC.query(dsn, "select * from test3")
#    println(size(df) == (2,7))
#    println( df[1][end-1] == 101)
#    println( df[1][end] == 102)
#    println( df[2][end-1] == "Steve")
    println( df[2][end-1])
#    println( df[2][end] == "Dean")
    println( df[2][end])
#    println( df[3][end-1] == "McQueen")
    println( df[3][end-1])
#    println( df[3][end] == "Martin")
    println( df[3][end])
    #println( df[4][end-1] == DecFP.Dec64(1))
    #println( df[4][end] == DecFP.Dec64(2))
#    println( df[5][end-1] == 100.0)
#    println( df[5][end] == 10.1)
#    println( df[6][end-1] == ODBC.API.SQLDate(2016,1,1))
#    println( df[6][end] == ODBC.API.SQLDate(2016,1,2))
#    println( df[7][end-1] == ODBC.API.SQLTimestamp(2016,1,1,0,0,0,0))
#    println( df[7][end] == ODBC.API.SQLTimestamp(2016,1,2,0,0,0,0))
    ODBC.execute!(dsn, "drop table if exists test2"))
    ODBC.execute!(dsn, "drop table if exists test3"))


ODBC.disconnect!(dsn)
