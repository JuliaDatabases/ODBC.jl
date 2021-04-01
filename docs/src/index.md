# ODBC.jl

```@contents
Depth = 3
```

The ODBC.jl package provides a Julia interface for the ODBC API as implemented by various ODBC driver managers. More specifically, it provides a prebuilt copy of iODBC and unixODBC for OSX/Linux platforms, while still relying on the system-provided libraries on Windows. This means that no extra installation of a driver manager is necessary after installing the ODBC.jl package like:

```julia
] add ODBC
```

Another common source of headache with ODBC is the various locations of configuration files on OSX/Linux; to remedy this, ODBC.jl writes and loads its own `odbc.ini` and `odbcinst.ini` configuration files in a "scratch space", as provided by the [Scratch.jl](https://github.com/JuliaPackaging/Scratch.jl) package. This ensures ODBC enviornment variables like `ODBCINI` are correctly set to the ODBC.jl managed config files. Additionally, ODBC.jl provides convenient ODBC administrative functions to add/remove drivers and dsns (see [`ODBC.addriver`](@ref) and [`ODBC.adddsn`](@ref)).

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

In setting up a DSN, you can specify all the configuration options once, then connect by just calling `ODBC.Connection("dsn name")` or `DBInterface.execute(ODBC.Connection, "dsn name")`, optionally passing a username and password as the 2nd and 3rd arguments. Alternatively, crafting and connecting via a fully specified connection string can mean less config-file dependency.

Note that connecting will use the currently "set" ODBC driver manager, which by default is iODBC on OSX, unixODBC on Linux, and
the system driver manager on Windows. If you experience cryptic connection errors, it's probably worth checking with your ODBC
driver documentation to see if it requires a specific driver manager. For example, Microsoft-provided ODBC driver for SQL Server
requires unixODBC on OSX, but by default, ODBC.jl sets the driver manager to iODBC, so before connecting, you would need to do:
```julia
ODBC.setunixODBC()
conn = ODBC.Connection(...)
```

Note that the odbc driver shared libraries can be "sticky" with regards to changing to
system configuration files. You may need to set a `OVERRIDE_ODBCJL_CONFIG` environment
variable before starting `julia` and running `import ODBC` to ensure that no environment
variables are changed by ODBC.jl itself. You can do this like:
```julia
ENV["OVERRIDE_ODBCJL_CONFIG"] = true
using ODBC
ODBC.setunixODBC(;ODBCSYSINI="/etc", ODBCINSTINI="odbcinst.ini", ODBCINI="/etc/odbc.ini")
conn = ODBC.Connection(...)
```

### Executing Queries

To execute queries, there are two paths:
  * `DBInterface.execute(conn, sql, params)`: directly execute a SQL query and return a `Cursor` for any resultset
  * `stmt = DBInterface.prepare(conn, sql); DBInterface.execute(stmt, params)`: first prepare a SQL statement, then execute, perhaps multiple times with different parameters
Both forms of `DBInterface.execute` return a `Cursor` object that satisfies the [Tables.jl](https://juliadata.github.io/Tables.jl/stable/), so results can be utilized in whichever way is most convenient, like `DataFrame(x)`, `CSV.write("results.csv", x)` or materialzed as a plain `Matrix` (`Tables.matrix(x)`), `NamedTuple` (`Tables.columntable(x)`), or `Vector` of `NamedTuple` (`Tables.rowtable(x)`).

An example of executing query is:

```julia
using DataFrames
df = DBInterface.execute(conn, "SELECT id, wage FROM employees") |> DataFrame
# if wage is a DecFP, maybe I want to convert to Float64 or Int64
# convert to Float64
df.wage = Float64.(df.wage)
# convert to Int64
df.wage = Int.(df.wage)
```

### Loading data

ODBC.jl attempts to provide a convenient `ODBC.load(table, conn, table_name)` function for generically loading Tables.jl-compatible sources into database tables. While the ODBC spec has some utilities for even making this possible, just note that it can be tricky to do generically in practice due to differences in database requirements for `CREATE TABLE` and column type statements.

## Troubleshooting

Using ODBC is notoriously complex on any system/language, so here's a collection of ideas/cases that have tripped people up in the past.

### Connection issues

If you're having connection issues, try to look up the documented requirements for the specific ODBC driver you're using; in particular, try to see if a specific driver manager is required, like iODBC or unixODBC. One example is in the Microsoft-provided SQL Server ODBC driver for mac/OSX which requires unixODBC as opposed to the usual OSX default iODBC. In ODBC.jl, you can easily switch between the two by just doing `ODBC.setunixODBC()` or `ODBC.setiODBC()`.

### Query mangling/unicode issues

Unicode support in ODBC is notoriously messy; different driver managers supports different things manually vs. automatically, drivers might require specific encodings or be flexible for all. ODBC.jl tries to stick with the most generally accepted defaults which is using the UTF-16 encoding in unixODBC and Windows, and using UTF-32 for OSX with iODBC. Sometimes, specific drivers will have configurations or allow datasource connection parameters to alter these. We don't recommend changing to anything but the defaults, but sometimes there are defaults shipped with drivers that don't match ODBC.jl's defaults. One example is the Impala ODBC driver on linux, which is correctly built against unixODBC (default driver manager on linux), but then sets a property `DriverManagerEncoding=UTF-32` in the `/opt/cloudera/impalaodbc/lib/64/cloudera.impalaodbc.ini` file which messes things up (since ODBC.jl tries to use UTF-16). This examples shows that there may be driver-provided configuration files that make affect things that sometimes take some digging to figure out. Always try to read through the driver documentation and keep an eye out for these kinds of settings, and then don't be afraid to snoop around in the installed files to see if anything seems out of place.

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
