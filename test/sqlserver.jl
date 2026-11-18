# Optional integration checks against SQL Server with a configured ODBC driver.
using ODBC, DBInterface, Tables, UUIDs, Dates, Test
ODBC.setunixODBC()
conn = ODBC.Connection(ENV["ODBC_TEST_SQLSERVER"]; user=ENV["ODBC_TEST_SQLSERVER_USER"], password=ENV["ODBC_TEST_SQLSERVER_PASSWORD"])
@testset "SQL Server release regressions" begin
    u = UUID("99685768-257e-462e-a29f-e6902550f030")
    DBInterface.execute(conn, "CREATE TABLE #release_check (id int, u uniqueidentifier, t nvarchar(max), b varbinary(max))")
    stmt = DBInterface.prepare(conn, "INSERT INTO #release_check VALUES (?, ?, ?, ?)")
    text = "望"^8001
    blob = UInt8[mod(i,256) for i in 1:100000]
    DBInterface.execute(stmt, (1,u,text,blob))
    DBInterface.execute(stmt, (2,missing,"",UInt8[]))
    DBInterface.close!(stmt)
    for rows in (false,true)
        r = Tables.columntable(DBInterface.execute(conn,"SELECT * FROM #release_check ORDER BY id"; iterate_rows=rows))
        @test isequal(r.u,[u,missing])
        @test all(isequal.(r.t, [text,""]))
        @test r.b == [blob,UInt8[]]
    end
    @test DBInterface.execute(Tables.columntable,conn,"SELECT LEN(?) AS n",(text,)).n == [8001]
    for text in ("望", "望"^2000, "😀"^3000, "plain")
        @test only(DBInterface.execute(Tables.columntable, conn, "SELECT CONVERT(nvarchar(max), ?) AS t", (text,)).t) == text
    end
    @test ODBC.sqltype(conn,Float64) == "float(53)" || ODBC.sqltype(conn,Float64) == "float"
    # DateTime columns are created as datetime2, whose lone "scale" parameter is not the reported column size
    DBInterface.execute(conn, "IF OBJECT_ID('load_datetime') IS NOT NULL DROP TABLE load_datetime")
    ODBC.load((d=[DateTime(2020, 1, 2, 3, 4, 5)],), conn, "load_datetime")
    @test DBInterface.execute(Tables.columntable, conn, "SELECT d FROM load_datetime").d == [DateTime(2020, 1, 2, 3, 4, 5)]
    DBInterface.execute(conn, "DROP TABLE load_datetime")
    stmt = DBInterface.prepare(conn,"SELECT CONVERT(uniqueidentifier, ?) AS u")
    @test DBInterface.execute(Tables.columntable,stmt,(u,)).u == [u]
    @test DBInterface.execute(Tables.columntable,stmt,(u,)).u == [u]
    DBInterface.close!(stmt)
    function temporarycursor()
        c=ODBC.Connection(ENV["ODBC_TEST_SQLSERVER"]; user=ENV["ODBC_TEST_SQLSERVER_USER"],password=ENV["ODBC_TEST_SQLSERVER_PASSWORD"])
        DBInterface.execute(c,"SELECT 42 AS n";iterate_rows=true)
    end
    c=temporarycursor();GC.gc();GC.gc()
    @test Tables.columntable(c).n == [42]
end
DBInterface.close!(conn)
