reload("ODBC")
using DataStreams, Base.Test, SQLite
ODBC.listdsns()
ODBC.listdrivers()
# db = SQLite.DB("odbc_test")
# dsn = ODBC.DSN("Driver={SQLite};Database=odbc_test")
#
# ODBC.query(dsn, "create table test1 (a int, b int)")
# ODBC.query(dsn, "insert into test1 values(1, 2)")
# ODBC.query(dsn, "select * from test1")
