#TODO
* Direct to file query result set: One of my top priorities. On a julia-dev conversation, it was mentioned trying to implement
a way for the user to specify a variety of ways to get results back (e.g. Any arrays, dataframes, direct to csv, etc).
* Metadata tools: This would involve specilized queries for examining DBMS schema, tables, views, columns, with 
associated metadata and possibly statistics. I know the driver managers support SQLTables and SQLStatistics, so it 
should be pretty simple to implement these.
* Create, Update Table functions (also auto-detect regular queries as these kinds of DDL queries): Pretty self-explanatory.
* Batch execute multiple queries: I seem to remember that this capability is DBMS-specific and sometimes auto-implemented (i.e. 
if my Query(querystring) contains multiple statements, it auto-executes). I need to research this some more and if it's pretty 
automated, we at least to need to figure out a way to return multiple resultsets
* Support more SQL data types: Date, Time, Intervals. Right now, all main bitstypes, character and binary formats
 (short, long, float, double, char, etc.) are supported (though not thoroughly tested), but the date and time data types are read as strings. Other
implementations in C use structs to read them in and Julia is still fragile on struct support as far as I know. I haven't 
spent a ton of time on this yet, so it's an eventual (I think the R package still only reads dates as strings...)
* Auto-textwrap; I can't get textwrap.jl to work on Windows right now, but something needs to be figured out for long queries.
(I attempted to copy/paste a few longer queries I run regularly and got some weird errors/issues, this may be a terminal
window size thing or something. I'm not well-versed in string buffer limitations enough to tell)
* Test on Linux, Mac?; 32-bit/64-bit; unixODBC, iODBC. Dev of this package has happened almost entirely on a windows
machine running 32-bit Julia. Very limited testing has happend on mac or linux (though I'm setting up a linux vm as I
write this). I'm sure there are tweaks to be made.
* Enter SQL Mode? Link to SQL parser? separate SQL prompt, save query history, sql" " string parser macro?:
My main thought here is to have something a little more helpful than the generic responses most DBMS give to SQL syntax
errors. My main goal would be able to specify the exact offending words/line. Utilizing a setup where the query string
is preceded by 'sql' (i.e sql"sel * from ...") would be a cool way to validate I think. I've done any work on this yet
but just no it's been a pain point for me working with command line querying vs. a few GUIs I've worked with before.
* SQLDriverConnect to connect directly to driver: I've already implemented the AdvancedConnect function for this, but
I think additional testing and documentation are needed to fully gain the power of the SQLDriverConnect function. Basically,
this function would allow someone to create a datasource or install a driver on the fly (through bringing up the ODBC
administrator window). 
* Asynchronous querying: This is just a hope and a prayer right now, but the later ODBC API supports async querying through
polling, so it would be cool to find a way to implement this. I'm not sure how useful it would be long term or exactly how
it would be implemented (Call asyncquery() and then later call querydone() to see if it's finished?), but because the underlying
api is capable this could be some cool functionality.
