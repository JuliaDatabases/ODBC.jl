
#include("ODBC.jl")

using ODBC;

#dsn = ODBC.DSN("Driver={Microsoft Access Driver (*.mdb, *.accdb)};Dbq=C:/Users/BC5234/Documents/04) DATA fournisseurs/ZZ_DATA/TRANSCO_STATIC_2017.accdb;";prompt=false) ;
#tbl = ODBC.query(dsn, "SELECT * FROM TRANSCO_ALPIQ_REPRISE;")
#ODBC.disconnect!(dsn)


#dsn = ODBC.DSN("toto_out");


dsn = ODBC.DSN("mysql_test","pascal","pascal");

ODBC.execute!(dsn, "drop table if exists test1")

ODBC.execute!(dsn, "create table test1 (test_char char(10))")


ODBC.execute!(dsn, "insert test1 VALUES ('éééééééééé')")

tbl = ODBC.query(dsn, "SELECT * FROM test1;")


ODBC.disconnect!(dsn)
