# ODBC.jl

The `ODBC.jl` package provides high-level julia functionality over the low-level ODBC API. In particular, the package allows making connections with any database that has a valid ODBC driver, sending SQL queries to those databases, and streaming the results into a variety of data sinks.

```@contents
Depth = 3
```

## ODBC administrative functions
```@docs
ODBC.drivers
ODBC.dsns
ODBC.adddriver
ODBC.removedriver
ODBC.adddsn
ODBC.removedsn
ODBC.setdebug
```

## DBMS Connections
```@docs
DBInterface.connect
ODBC.Connection
DBInterface.close!
```

## Query execution and result handling
```@docs
DBInterface.prepare
DBInterface.execute
DBInterface.executemultiple
```
