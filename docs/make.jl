using Documenter, ODBC

makedocs(
    modules = [ODBC],
)

deploydocs(
    deps = Deps.pip("mkdocs", "mkdocs-material", "python-markdown-math"),
    repo = "github.com/JuliaDB/ODBC.jl.git"
)
