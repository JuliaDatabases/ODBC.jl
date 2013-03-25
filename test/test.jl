#The MySQL Driver must be previously installed

using DataFrames
using ODBC
listdsns()
listdrivers()
advancedconnect("Driver={MySQL ODBC 3.51 Driver};Server=ensembldb.ensembl.org;Port=5306;User=anonymous;Option=3;",ODBC.SQL_DRIVER_NOPROMPT)

query("use homo_sapiens_vega_69_37")
query("select count(*) from exon")
query("show columns from exon")
query("select * from exon where phase = 2")
#DBMS may not support batch statements
query("select count(*) from exon; select count(*) from exon;")
#Write results to a file (delimiter can be specified as Char arg after filename; default is ',')
query("select count(*) from exon","test.csv")
query("select * from exon where phase = 2","test.csv")

querymeta("select count(*) from exon")

disconnect(conn)
