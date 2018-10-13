# ODBC.jl

The `ODBC.jl` package provides high-level julia functionality over the low-level ODBC API middleware. In particular, the package allows making connections with any database that has a valid ODBC driver, sending SQL queries to those databases, and streaming the results into a variety of data sinks.

### `ODBC.dsns()`

Lists pre-configured DSN datasources available to the user. Note that DSNs are "bit-specific", meaning a 32-bit DSN setup with the 32-bit ODBC system admin console will only be accessible through 32-bit julia.

### `ODBC.drivers`

Lists valid ODBC drivers on the system which can be used manually in connection strings in the form of `Driver={ODBC Driver Name};` as a key-value pair. Valid drivers are read from the system ODBC library, which can be seen by calling `ODBC.API.odbc_dm`. This library is "detected" automatically when the ODBC.jl package is loaded, but can also be set by calling `ODBC.API.setODBC("manual_odbc_lib")`.


### `ODBC.DSN`

Constructors:

`ODBC.DSN(dsn, username, password) => ODBC.DSN`

`ODBC.DSN(connection_string; prompt::Bool=true) => ODBC.DSN`

`ODBC.disconnect!(dsn::ODBC.DSN)`

The first method attempts to connect to a pre-defined DSN that has been pre-configured through your system's ODBC admin console. Settings such as the ODBC driver, server address, port #, etc. are already configured, so all that is required is the username and password to connect.

The second method takes a full connection string. Connection strings are vendor-specific, but follow the format of `key1=value1;key2=value2...` for various key-value pairs, typically including `Driver=X` and `Server=Y`. For help in figuring out how to build the right connection string for your system, see [connectionstrings.com](https://www.connectionstrings.com/). There is also a `prompt` keyword argument that indicates whether a driver-specific UI window should be shown if there are missing connection string key-value pairs needed for connection. If being run non-interactively, set `prompt=false`.

`ODBC.disconnect!(dsn)` can also be used to disconnect the database connection.

### `ODBC.query`

`sql>` REPL mode:

The ODBC.jl package ships an experimental REPL mode for convenience in rapid query execution. The REPL mode can be accessed by hitting the `]` character at an empty `julia>` prompt. The prompt will change to `sql>` and SQL queries can be entered directly and executed by pressing `enter`. Since the queries need an `ODBC.DSN` to execute against, the most recently connected `ODBC.DSN` is used automatically, so a valid connection must have been created before entering the `sql>` REPL mode. Query results are shown directly in the REPL, and the prompt will stay in `sql>` mode until `backspace` is pressed at an empty `sql>` prompt. The results of the last query can then be accessed back at the `julia>` prompt via the global `odbcdf` variable.

`ODBC.query(dsn::ODBC.DSN, sql::AbstractString)`
`ODBC.Query(dsn::ODBC.DSN, sql::AbstractString) |> DataFrame`
`ODBC.Query(dsn::ODBC.DSN, sql::AbstractString) |> CSV.write("output.csv")`
`ODBC.Query(dsn::ODBC.DSN, sql::AbstractString) |> SQLite.load!(db, table_name)`
`ODBC.Query(dsn::ODBC.DSN, sql::AbstractString) |> Feather.write("output.feather")`

`ODBC.query` is a high-level method for sending an SQL statement to a system and returning the results. As is shown, a valid `dsn::ODBC.DSN` and SQL statement `sql` combo are the arguments. By default, the results will be returned in a [`DataFrame`](http://juliadata.github.io/DataFrames.jl/latest/), but a variety of options exist for handling  results, including `CSV.write`, `SQLite.load!`, or `Feather.write`. `ODBC.Query` executes a query and returns metadata about the return results and satisfies the [Tables.jl](https://github.com/JuliaData/Tables.jl) interface for allowing integration with the numerous other formats.

Examples:

```julia
dsn = ODBC.DSN(valid_dsn)

# return result as a DataFrame
df = ODBC.query(dsn, "select * from cool_table")

# return result as a csv file
using CSV
csv = ODBC.Query(dsn, "select * from cool_table") |> CSV.write("cool_table.csv")

# return the result directly into a local SQLite table
using SQLite
db = SQLite.DB()

sqlite = ODBC.Query(dsn, "select * from cool_table") |> SQLite.load!(db, "cool_table_in_sqlite")

# return the result as a feather-formatted binary file
using Feather
feather = ODBC.Query(dsn, "select * from cool_table") |> Feather.write("cool_table.feather")

```

### `ODBC.load!`

Methods:
`ODBC.load!(table, dsn::DSN, tablename::AbstractString)`

**Please note this is currently experimental and ODBC driver-dependent; meaning, an ODBC driver must impelement certain low-level API methods to enable this feature. This is not a limitation of ODBC.jl itself, but the ODBC driver provided by the vendor. In the case this method doesn't work for loading data, please see the documentation around prepared statements.**

`ODBC.load!` takes a valid DB connection `dsn` and the name of an *existing* table `tablename` to which to send data. Note that on-the-fly creation of a table is not currently supported. The data to send can be any valid [`Tables.jl`](https://github.com/JuliaData/Tables.jl) implementor, from the `Tables.jl` framework, including a `DataFrame`, `CSV.File`, `SQLite.Query`, etc.

Examples:

```julia
dsn = ODBC.DSN(valid_dsn)

# first create a remote table
ODBC.execute!(dsn, "CREATE TABLE cool_table (col1 INT, col2 FLOAT, col3 VARCHAR)")

# load data from a DataFrame into the table
df = DataFrame(col1=[1,2,3], col2=[4.0, 5.0, 6.0], col3=["hey", "there", "sailor"])

ODBC.load!(dsn, "cool_table", df)

# load data from a csv file
using CSV

ODBC.load!(dsn, "cool_table", CSV.File("cool_table.csv"))

# load data from an SQLite table
using SQLite

db = SQLite.DB()
ODBC.load!(dsn, "cool_table", SQLite.Query(db, "select * from cool_table"))

```


### `ODBC.prepare`

Methods:

`ODBC.prepare(dsn::ODBC.DSN, querystring::String) => ODBC.Statement`

Prepare an SQL statement `querystring` against the DB and return it as an `ODBC.Statement`. This `ODBC.Statement` can then be executed once, or repeatedly in a more efficient manner than `ODBC.execute!(dsn, querystring)`. Prepared statements can also support parameter place-holders that can be filled in dynamically before executing; this is a common strategy for bulk-loading data or other statements that need to be bulk-executed with changing simple parameters before each execution. Consult your DB/vendor-specific SQL syntax for the exact specifications for parameters.

Examples:

```julia
# prepare a statement with 3 parameters marked by the '?' character
stmt = ODBC.prepare(dsn, "INSERT INTO cool_table VALUES(?, ?, ?)")

# a DataFrame with data we'd like to insert into a table
df = DataFrame(col1=[1,2,3], col2=[4.0, 5.0, 6.0], col3=["hey", "there", "sailor"])

for row = 1:size(df, 1)
    # each time we execute the `stmt`, we pass another row to be bound to the parameters
    ODBC.execute!(stmt, [df[row, x] for x = 1:size(df, 2)])
end
```


### `ODBC.execute!`

Methods:

`ODBC.execute!(dsn::ODBC.DSN, querystring::String)`

`ODBC.execute!(stmt::ODBC.Statement)`

`ODBC.execute!(stmt::ODBC.Statement, values)`


`ODBC.execute!` provides a method for executing a statement against a DB without returning any results. Certain SQL statements known as "DDL" statements are used to modify objects in a DB and don't have results to return anyway. While `ODBC.query` can still be used for these types of statements, `ODBC.execute!` is much more efficient. This method is also used to execute prepared statements, as noted in the documentation for `ODBC.prepare`.


### `ODBC.Query`

Constructors:

`ODBC.Query(dsn::ODBC.DSN, querystring::String) => ODBC.Query`

`ODBC.Query` is an implementation of the [Tables.jl](https://github.com/JuliaData/Tables.jl) interface. It takes a valid DB connection `dsn` and executes a properly formatted SQL query string `querystring` and makes preparations for returning a resultset.
