dir = joinpath(@__DIR__, "../config")
isdir(dir) || mkdir(dir)

if !isfile(joinpath(dir, "odbc.ini"))
    open(joinpath(dir, "odbc.ini"), "w") do io
        write(io, "[ODBC Data Sources]\n\n[ODBC]\nTrace=0\nTraceFile=stderr\n")
    end
end

if !isfile(joinpath(dir, "odbcinst.ini"))
    open(joinpath(dir, "odbcinst.ini"), "w") do io
        write(io, "[ODBC Drivers]\n")
    end
end
