using Documenter, ODBC

makedocs(
    modules = [ODBC],
    sitename = "ODBC.jl",
    checkdocs = :all,
    format = Documenter.HTML(edit_link = "main"),
    pages = ["Home" => "index.md"]
)

deploydocs(
    repo = "github.com/JuliaDatabases/ODBC.jl.git",
    target = "build",
    devbranch = "main"
)
