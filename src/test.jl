
include("ODBC.jl")


dsn = ODBC.DSN("Driver={Microsoft Access Driver (*.mdb, *.accdb)};Dbq=C:/Users/BC5234/Documents/04) DATA fournisseurs/ZZ_DATA/TRANSCO_STATIC_2017.accdb;";prompt=false) ;
tbl = ODBC.query(dsn, "SELECT * FROM TRANSCO_ALPIQ_REPRISE;")
ODBC.disconnect!(dsn)
