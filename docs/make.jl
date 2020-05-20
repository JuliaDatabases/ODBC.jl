using Documenter, ODBC

makedocs(
    modules = [ODBC],
    sitename = "ODBC.jl",
    pages = ["Home" => "index.md"]
)

deploydocs(
    repo = "github.com/JuliaDatabases/ODBC.jl.git",
    target = "build"
)
