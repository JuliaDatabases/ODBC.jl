# ODBC.jl

```@contents
Depth = 3
```

The ODBC.jl package provides a Julia interface for the ODBC API as implemented by various ODBC driver managers. More specifically, it provides a prebuilt copy of iODBC and unixODBC for OSX/Linux platforms, while still relying on the system-provided libraries on Windows. This means that no extra installation of a driver manager is necessary after installing the ODBC.jl package like:

```julia
] add ODBC
```

Another common source of headache with ODBC is the various locations of configuration files on OSX/Linux; to remedy this, ODBC.jl writes and loads its own `odbc.ini` and `odbcinst.ini` configuration files inside the package directory, like `ODBC/config/odbc.ini`. This ensures ODBC enviornment variables like `ODBCINI` are correctly set to the ODBC.jl managed config files. Additionally, ODBC.jl provides convenient ODBC administrative functions to add/remove drivers and dsns (see [`ODBC.addriver`](@ref) and [`ODBC.adddsn`](@ref)).

What this all means is that hopefully ODBC.jl provides the easiest setup experience possible for a slightly dated API that is known for configuration complexities.

## Getting Started

Once ODBC.jl is installed, you'll want, at a minimum, to configure ODBC drivers for the specific databases you'll be connecting to. A reminder on ODBC architecture that each database must build/distribute their own compliant ODBC driver that can talk with the ODBC.jl-provided driver manager to make connections, execute queries, etc. What's more, individual database drivers must often build against a specific driver manager (or specific driver manager per platform). By default, ODBC.jl will use iODBC as driver manager on OSX, unixODBC on Linux platforms, and the system-provided driver manager on Windows. If a database driver mentions a requirement for a specific driver manager, ODBC.jl provides a way to switch between them, even at run-time (see [`ODBC.setiODBC`](@ref) and [`ODBC.setunixODBC`](@ref)).

To install an ODBC driver, you can call:
```julia
ODBC.adddriver("name of driver", "full, absolute path to driver shared library"; kw...)
```
passing the name of the driver, the full, absolute path to the driver shared library, and any additional keyword arguments which will be included as `KEY=VALUE` pairs in the `.ini` config files. ***NOTE*** on Windows, you likely need to start Julia (or your terminal) with administrative privileges (like ctrl + right-click the application, then choose open as admin) in order to add drivers via ODBC like this.

### Connections

Once a driver or two are installed (viewable by calling `ODBC.drivers()`), you can either:
  * Setup a DSN, via `ODBC.adddsn("dsn name", "driver name"; kw...)`
  * Make a connection directly by using a full connection string like `ODBC.Connection(connection_string)`

In setting up a DSN, you can specify all the configuration options once, then connect by just calling `ODBC.Connection("dsn name")`, optionally passing a username and password as the 2nd and 3rd arguments. Alternatively, crafting and connecting via a fully specified connection string can mean less config-file dependency.

### Executing Queries

To execute queries, there are two paths:
  * `DBInterface.execute(conn, sql, params)`: directly execute a SQL query and return a `Cursor` for any resultset
  * `stmt = DBInterface.prepare(conn, sql); DBInterface.execute(stmt, params)`: first prepare a SQL statement, then execute, perhaps multiple times with different parameters
Both forms of `DBInterface.execute` return a `Cursor` object that satisfies the [Tables.jl](https://juliadata.github.io/Tables.jl/stable/), so results can be utilized in whichever way is most convenient, like `DataFrame(x)`, `CSV.write("results.csv", x)` or materialzed as a plain `Matrix` (`Tables.matrix(x)`), `NamedTuple` (`Tables.columntable(x)`), or `Vector` of `NamedTuple` (`Tables.rowtable(x)`).

### Loading data

ODBC.jl attempts to provide a convenient `ODBC.load(table, conn, table_name)` function for generically loading Tables.jl-compatible sources into database tables. While the ODBC spec has some utilities for even making this possible, just note that it can be tricky to do generically in practice due to differences in database requirements for `CREATE TABLE` and column type statements.

## API Reference

### DBMS Connections
```@docs
DBInterface.connect
ODBC.Connection
DBInterface.close!
```

### Query execution and result handling
```@docs
DBInterface.prepare
DBInterface.execute
DBInterface.executemultiple
```

### Data loading
```@docs
ODBC.load
```

### ODBC administrative functions
```@docs
ODBC.drivers
ODBC.dsns
ODBC.adddriver
ODBC.removedriver
ODBC.adddsn
ODBC.removedsn
ODBC.setdebug
```
