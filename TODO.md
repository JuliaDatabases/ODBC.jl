TODO
=====
* Large resultset REPL crash when not saving to a file?
* Polish readthedocs-style documentation
* Create SQL typealiases and use in conjunction with Julia-C typealiases for ODBC_API
* Metadata tools: This would involve specilized queries for examining DBMS schema, tables, views, columns, with 
associated metadata and possibly statistics. I know the driver managers support SQLTables and SQLStatistics, so it 
should be pretty simple to implement these.
* Create, Update Table functions (also auto-detect regular queries as these kinds of DDL queries): Pretty self-explanatory.
* Support more SQL data types: Date, Time, Intervals. Right now, all main bitstypes, character and binary formats
 (short, long, float, double, char, etc.) are supported (though not thoroughly tested), but the date and time data types are read as strings. Other
implementations in C use structs to read them in and Julia is still fragile on struct support as far as I know. I haven't 
spent a ton of time on this yet, so it's an eventual (I think the R package still only reads dates as strings...)
* Asynchronous querying: This is just a hope and a prayer right now, but the later ODBC API supports async querying through
polling, so it would be cool to find a way to implement this. I'm not sure how useful it would be long term or exactly how
it would be implemented (Call asyncquery() and then later call querydone() to see if it's finished?), but because the underlying
api is capable this could be some cool functionality.
* How to deal with Unicode/ANSI function calling?
