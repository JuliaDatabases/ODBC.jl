using Documenter, ODBC

makedocs(
    modules = [ODBC],
    format = :html,
    sitename = "ODBC.jl",
    pages = ["Home" => "index.md"]
)

deploydocs(
    repo = "github.com/JuliaDatabases/ODBC.jl.git",
    target = "build",
    deps = nothing,
    make = nothing,
    julia = "0.5",
    osname = "linux"
)
