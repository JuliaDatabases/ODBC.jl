ODBC.jl
=======

A low-level ODBC interface for the Julia programming language

Installation through the Julia package manager:
```julia
julia> Pkg.init()        # Creates julia package repository (only runs once for all packages)
julia> Pkg.add("ODBC")   # Creates the ODBC repo folder and downloads the ODBC package + dependancy (if needed)
julia> using ODBC        # Loads the ODBC module for use (needs to be run with each new Julia instance)
```
## Package Documentation
Exported functions, macros, types, and variables include:
#### Functions
* `ODBC.connect(dsn; usr="", pwd="")`

  `ODBC.connect` requires the `dsn` string argument as the name of a pre-defined ODBC
datasource.  Valid datasources (DSNs) must first be setup through the ODBC
administrator (or IODBC, unixODBC, etc.) prior to connecting in Julia. Note the use of `ODBC.` before `connect`, this is to prevent method ambiguity with the `Base.connect` family of methods.

  The `usr` and `pwd` named arguments are optional as they may already
be defined in the datasource.

  `ODBC.connect` returns a `Connection` type which contains basic information
about the connection and ODBC handle pointers.

  `ODBC.connect` can be used by storing the `Connection` type in
a variable to be able to disconnect or facilitate handling multiple
connections like so:
  ```julia
  co = ODBC.connect("mydatasource",usr="johndoe",pwd="12345")
  ```
  But it's unneccesary to store the `Connection`, as an exported
`conn` variable holds the most recently created `Connection` type and other
ODBC functions (i.e. `query`) will use it by default in the absence of a specified
connection.

* `disconnect(connection::Connection=conn)`

  `disconnect` closes a connection type, frees all handles and resets
the default connection `conn` as necessary. If invoked with no arguments
(i.e. `disconnect()`), the default connection `conn` is closed.

* `advancedconnect(conn_string::String)`

  `advancedconnect` implements the native ODBC SQLDriverConnect function
which allows flexibility in connecting to a datasource through specifying
a 'connection string' (e.g. "DSN=userdsn;UID=johnjacob;PWD=jingle;") See
ODBC API documentation (http://goo.gl/uXTuk) for additional details.

  If the connection string doesn't contain enough information for the driver
to connect, the user will be prompted with the additional information
needed.

  Furthermore, on Windows, if `advancedconnect()` is called without arguments the ODBC
administrator will be brought up where the user can select the DSN to
which to connect, even allowing the user to create a datasource or add a
driver.

  (An excellent resource for learning how to construct connection strings
for various DBMS/driver configurations is
http://www.connectionstrings.com/)

* `query(connection::Connection=conn, querystring; file=:DataFrame,delim='\t')`
  
  If a connection type isn't specified as the first positional argument, the query will be executed against
the default connection (stored in the exported variable `conn` if you'd like to
inspect).

  Once the query is executed, the resultset is stored in a
`DataFrame` by default (`file=:DataFrame`). Otherwise, the user may specify
a file name to which the resultset is to be written, along with the desired
file delimiter (default `delim='\t'`). Depending on DBMS capability, users may also
pass multiple query statements in a single query call and the resultsets
will be returned in an array of DataFrames, or the user may specify an array
of filename strings and `Char` delimiters into which the results will be written. 

  For the general user, a simple `query(querystring)` is enough to return a single
resultset in a DataFrame. Results are stored in the passed connection type's resultset field.
(i.e. `conn.resultset`). Results are stored by default to avoid immediate garbarge collection
and provide access for the user even if the resultset returned by `query()` isn't stored in a variable.

* `querymeta(conn::Connection=conn, querystring; file=:DataFrame,delim='\t')`
 
  `querymeta` is really just the 1st half of the `query` function. A query string is sent to the DBMS, executed,
and metadata (i.e. rows, columns, types, column names, etc.) is returned to the user, avoiding actually returning
the dataset. The returned information is actually stored in the `Metadata` type, so the information may be
programmatically examined (try running `names(Metadata)` to see its fields). Running `querymeta` is useful 
for inspecting the results of large queries while avoiding the overhead of returning the actual dataset into memory.
The function signature is identical to `query` for ease in switching between the two though `querymeta` ignores
the `file` and `delim` arguments.

* `listdrivers()`

  Takes no arguments. Returns a list of installed ODBC drivers registered in the ODBC administator (IODBC, unixODBC, etc.).
* `listdsns()`

  Takes no arguments. Returns a list of defined datasources (DSNs) registered in the ODBC administator 
  (IODBC, unixODBC, etc.). The datasource names can be used as the 1st argument in `ODBC.connect(dsn)`.
#### Macros
* `sql"..."`

  `sql"..."` is a Julia string literal implemented by the `@sql_str` macro. It is equivalent to calling 
  `query(querystring)` as you can see from the actual definition below:
  ```julia
  macro sql_str(s)
    query(s)
  end
  ```
#### Types
* `Connection`

  Stores information about a DSN connection. Names include `dsn`, `number` (counts `Connection` types specific
to each DSN), `dbc_ptr` and `stmt_ptr` as internal connection and statement handle pointers, and `resultset` which
stores the last resultset returned from a `query` or `querymeta` call. 

* `Metadata`
  Stores information about an executed query, returned by `querymeta`. Names include `querystring` (the query sent to
be executed), `cols` (# of columns in resultset), `rows` (# of rows in resultset), `colnames` (column names to be 
returned in resultset), `coltypes` (SQL types of resultset columns), `colsizes` (size in bytes of resultset columns),
`coldigits` (max number of digits for numeric resultset columns; though not always implemented correctly by ODBC driver),
and `colnulls` (whether the resultset column is nullable).
#### Variables
* `conn`
  Global, exported variable that initially holds a null `Connection` type until a connection is successfully made by
`ODBC.connect` or `advancedconnect`. Is used by `query` and `querymeta` as the default datasource `Connection` if none is
explicitly specified. 
* `Connections`
  Global, exported variable of type `Array{Connection,1}`, that holds `Connection` types. When multiple calls to `ODBC.connect`
or `advancedconnect` are made, `Connections` stores each `Connection` type to manage the number of DSN connections. 
It is also referenced when the default connection `conn` is disconnected and reset to `Connections[end]` if other 
connections exist, or a null `Connection` type otherwise.

### Known Issues
* We've had limited ODBC testing between various platforms, so it may happen that `ODBC.jl` doesn't recognize your
  ODBC shared library (also know as the Driver Manager, basically the middleman between `ODBC.jl` and the RDBMS).
  The current approach is to check a variety of the most widely used ODBC libraries and produce an error if not found.
  If this happens, you'll need to manually locate your ODBC shared library (searching for something along the lines of
  `libodbc` or `libiodbc`, or installing it if you haven't yet) and then run the following:
  ```julia
  const odbc_dm = "path/to/library/libodbc.so" (or .dylib on OSX)
  ```

  *Note that the file is `odbc32` on Windows, but should never have a problem being found (ships by default).
  That said, if you end up doing this, open an issue on GitHub to let me know what the name of your ODBC library is
and I can add is as one of the defaults to check for.

### TODO
* Create SQL typealiases and use in conjunction with Julia-C typealiases for ODBC_API (for more transparency and because we can)
* Metadata tools: This would involve specilized queries for examining DBMS schema, tables, views, columns, with 
  associated metadata and possibly statistics. I know the driver managers support SQLTables and SQLStatistics, 
  so it should be pretty simple to implement these.
* Create, Update Table functions (also auto-detect regular queries as these kinds of DDL queries): Pretty self-explanatory.
* Support more SQL data types: Date, Time, Intervals. Right now, all main bitstypes, character and binary formats
  (short, long, float, double, char, etc.) are supported, but the date and time data types are read as strings. 
  Other implementations in C use structs to read them in and Julia is still fragile on struct support as far as I know.
  As Julia struct compatibility improves it's an eventual (I think RODBC package still only reads dates as strings...)
* Asynchronous querying: This might be a longshot, but the later ODBC API supports async querying through polling, 
  so it would be cool to find a way to implement this. I'm not sure how useful it would be long term or exactly how it
  would be implemented (Call asyncquery() and then later call querydone() to see if it's finished?), but because the
  underlying api is capable this could be some cool functionality.
* How to deal with Unicode/ANSI function calling? (I think we're ok here, but not sure)
