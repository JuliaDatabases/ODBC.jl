#The MySQL Driver must be previously installed

reload("ODBC")
ODBC.listdsns()
ODBC.listdrivers()
co = ODBC.advancedconnect("Driver={MySQL Unicode};Server=ensembldb.ensembl.org;User=anonymous")

ODBC.query(co,"use homo_sapiens_vega_69_37")
ODBC.query(co,"select count(*) from exon")
ODBC.query(co,"show columns from exon")
ODBC.query(co,"select phase from exon group by phase")
ODBC.query(co,"select a.exon_id, b.stable_id 
	from exon a 
	left outer join exon b on a.seq_region_id = b.seq_region_id
	where a.phase = 2 and b.phase = 0")
ODBC.query(co,"select * from exon where phase = -1")
ODBC.query(co,"select count(*) from exon where phase = 0")
ODBC.query(co,"select * from exon where phase = 2 limit 20")
#DBMS may not support batch statements
ODBC.query(co,"select count(*) from exon; select count(*) from exon;")
#Write results to a file (delimiter can be specified as Char arg after filename; default is ',')
ODBC.query(co,"select count(*) from exon","test.csv")
ODBC.query(co,"select * from exon where phase = 2","test.csv")

ODBC.querymeta(co,"select count(*) from exon")

disconnect(conn)
