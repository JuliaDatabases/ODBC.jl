#The MySQL Driver must be previously installed

reload("ODBC")
using DataStreams, Base.Test
ODBC.listdsns()
ODBC.listdrivers()
dsn = ODBC.DSN("Driver={MySQL Unicode};Server=ensembldb.ensembl.org;User=anonymous")
# dsn = ODBC.DSN("Driver={MySQL ODBC 5.3 Unicode Driver};Server=ensembldb.ensembl.org;User=anonymous")
source = ODBC.Source(dsn,"SHOW DATABASES")
dt = Data.stream!(source, Data.Table)
@test size(dt) == (5078,1)
@test eltype(dt.data[1]) == Nullable{Data.PointerString{ODBC.API.SQLWCHAR}}

source = ODBC.Source(dsn,"use homo_sapiens_vega_69_37")
@test Data.isdone(source)
dt = Data.stream!(source, Data.Table)
@test isempty(dt.data)
@test size(dt) == (0,0)

source = ODBC.Source(dsn,"select count(*) from exon")
dt = Data.stream!(source, Data.Table)
@test size(dt) == (1,1)
@test Data.header(dt) == ["count(*)"]
@test get(dt.data[1][1]) == 648378
@test eltype(dt.data[1]) == Nullable{Int}

source = ODBC.Source(dsn,"show columns from exon")
dt = Data.stream!(source, Data.Table)
@test Data.header(dt) == ["Field","Type","Null","Key","Default","Extra"]

source = ODBC.Source(dsn,"select phase from exon group by phase order by phase")
dt = Data.stream!(source, Data.Table)
@test Data.header(dt) == ["phase"]
@test get(dt.data[1][1]) === Int8(-1)
@test eltype(dt.data[1]) == Nullable{Int8}

# test "multi-fetch" query
source = ODBC.Source(dsn,"select * from exon where phase = -1")
dt = Data.stream!(source, Data.Table)
@test size(dt) == (385100,13)

source = ODBC.Source(dsn,"select count(*) from exon where phase = 0")
dt = Data.stream!(source, Data.Table)
source = ODBC.Source(dsn,"select * from exon where phase = 2 limit 20")
dt = Data.stream!(source, Data.Table)

source = ODBC.Source(dsn,"select CONVERT(stable_id USING ascii) as stable_id from exon where phase = 2 limit 20")
dt = Data.stream!(source, Data.Table)

source = ODBC.Source(dsn,"select CONVERT(stable_id USING ucs2) as stable_id from exon where phase = 2 limit 20")
dt = Data.stream!(source, Data.Table)

source = ODBC.Source(dsn,"select CONVERT(stable_id USING binary) as stable_id from exon where phase = 2 limit 20")
dt = Data.stream!(source, Data.Table)

source = ODBC.Source(dsn,"select CONVERT(stable_id USING latin1) as stable_id from exon where phase = 2 limit 20")
dt = Data.stream!(source, Data.Table)

#DBMS may not support batch statements
source = ODBC.Source(dsn,"select count(*) from exon; select count(*) from exon;")
dt = Data.stream!(source, Data.Table)
#Write results to a file (delimiter can be specified as Char arg after filename; default is ',')
source = ODBC.Source(dsn,"select count(*) from exon","test.csv")
dt = Data.stream!(source, Data.Table)
source = ODBC.Source(dsn,"select * from exon where phase = 2","test.csv")
dt = Data.stream!(source, Data.Table)

disconnect(conn)
