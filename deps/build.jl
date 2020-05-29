dir = joinpath(@__DIR__, "../config")
mkdir(dir)
open(joinpath(dir, "odbc.ini"), "w") do io
    write(io, "[ODBC Data Sources]\n\n[ODBC]\nTrace=0\nTraceFile=stderr\n")
end

open(joinpath(dir, "odbcinst.ini"), "w") do io
    write(io, "[ODBC Drivers]\n")
end
