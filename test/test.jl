#The MySQL Driver must be previously installed

using DataFrames
using ODBC
listdsns()
listdrivers()
# ODBC.connect("test")

# query("use homo_sapiens_vega_69_37")
# query("select count(*) from exon")
# query("show columns from exon")
# query("select phase from exon group by phase")
# query("select a.exon_id, b.stable_id
# 	from exon a
# 	left outer join exon b on a.seq_region_id = b.seq_region_id
# 	where a.phase = 2 and b.phase = 0")
# query("select * from exon where phase = -1")
# query("select count(*) from exon where phase = 0")
# query("select * from exon where phase = 2 limit 20")
# #DBMS may not support batch statements
# query("select count(*) from exon; select count(*) from exon;")
# #Write results to a file (delimiter can be specified as Char arg after filename; default is ',')
# query("select count(*) from exon","test.csv")
# query("select * from exon where phase = 2","test.csv")

# querymeta("select count(*) from exon")

# disconnect(conn)
