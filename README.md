ODBC.jl
=======
[![ODBC](http://pkg.julialang.org/badges/ODBC_0.4.svg)](http://pkg.julialang.org/?pkg=ODBC&ver=0.4)
[![ODBC](http://pkg.julialang.org/badges/ODBC_0.5.svg)](http://pkg.julialang.org/?pkg=ODBC&ver=0.5)

Linux: [![Build Status](https://travis-ci.org/JuliaDB/ODBC.jl.svg?branch=master)](https://travis-ci.org/JuliaDB/ODBC.jl)

Windows: [![Build Status](https://ci.appveyor.com/api/projects/status/github/JuliaDB/ODBC.jl?branch=master&svg=true)](https://ci.appveyor.com/project/JuliaDB/odbc-jl/branch/master)

An ODBC interface for the Julia programming language

Installation through the Julia package manager:
```julia
julia> Pkg.init()        # Creates julia package repository (only runs once for all packages)
julia> Pkg.add("ODBC")   # Creates the ODBC repo folder and downloads the ODBC package + dependancy (if needed)
julia> using ODBC        # Loads the ODBC module for use (needs to be run with each new Julia instance)
```

Basic Usage:
```julia
using ODBC

# list installed ODBC drivers
ODBC.listdrivers()
# list pre-defined ODBC DSNs
ODBC.listdsns()

# connect to a DSN using a pre-defined DSN or custom connection string
dsn = ODBC.DSN("pre_defined_DSN","username","password")

# Basic a basic query that returns results at a Data.Table by default
dbs = ODBC.query(dsn, "show databases")

# Execute a query without returning results
ODBC.execute!(dsn, "use mydb")

# return query results as a CSV file
csv = CSV.Sink("mydb_tables.csv")
data = ODBC.query(dsn, "select table_name from information_schema.tables", csv);

# return query results in an SQLite table
db = SQLite.DB()
source = ODBC.Source(dsn, "select table_name from information_schema.tables")
sqlite = SQLite.Sink(source, db)
Data.stream!(source, sqlite)
```

Use the automatic help mode for more information on package types/functions.
