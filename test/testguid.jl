import ODBC
using Test

u = Base.UUID("11223344-5566-7788-99aa-bbccddeeff01")

@test u === Base.convert(Base.UUID, ODBC.API.GUID(u))