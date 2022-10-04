mutable struct Connection <: DBInterface.Connection
    dbc::API.Handle
    dsn::String
    quoteidentifierchar::Char
    types::Dict{Type, String}
    alltypes::Any
    cursorstmt::Any # keep track of most recent stmt cursor to free appropriately before next execute
    stmts::WeakKeyDict{Any, Any}
end

Connection(dbc::API.Handle, dsn) = Connection(dbc, dsn, '\0', Dict{Type, String}(), nothing, nothing, WeakKeyDict())

Base.show(io::IO, conn::Connection) = print(io, "ODBC.Connection($(conn.dsn))")

# make sure any previous open cursors are closed on the connection
function clear!(conn::Connection)
    if conn.cursorstmt !== nothing
        API.freestmt(conn.cursorstmt)
        conn.cursorstmt = nothing
    end
    return
end

# format usr, pwd, and extraauth into UID=user;PWD=pass;extraauth
function getextraauth(usr::Union{AbstractString, Nothing}, pwd::Union{AbstractString, Nothing}, extraauth::Union{AbstractString, Nothing}) :: String
    parts = [
        usr === nothing ? nothing : "UID={$usr}",
        pwd === nothing ? nothing : "PWD={$pwd}",
        extraauth === nothing ? nothing : extraauth
    ]
    strings = filter(s -> s !== nothing, parts)
    return join(strings, ";")
end

"""
    ODBC.Connection(dsn_or_connectionstring; user, password, extraauth)

Construct a `Connection` type by connecting to a valid ODBC Connection or by specifying a datasource name or valid connection string.
1st argument `dsn` can be either the name of a pre-defined ODBC Connection or a valid connection string.
A great resource for building valid connection strings is [http://www.connectionstrings.com/](http://www.connectionstrings.com/).
Takes optional keyword arguments `username`, `password`, and `extraauth`, which are used to specify auth parameters. `extraauth` is
to allow you to pass a sensitive string to be appended verbatim to the end of the connection string, e.g. DB-specific auth token
parameters.

Note that connecting will use the currently "set" ODBC driver manager, which by default is iODBC on OSX, unixODBC on Linux, and
the system driver manager on Windows. If you experience cryptic connection errors, it's probably worth checking with your ODBC
driver documentation to see if it requires a specific driver manager. For example, Microsoft-provided ODBC driver for SQL Server
requires unixODBC on OSX, but by default, ODBC.jl sets the driver manager to iODBC, so before connecting, you would need to do:
```julia
ODBC.setunixODBC()
conn = ODBC.Connection(...)
```
"""
function Connection(dsn::AbstractString; user=nothing, password=nothing, extraauth=nothing)
    connstr = occursin('=', dsn) ? dsn : "DSN=$dsn"
    extraauth = getextraauth(user, password, extraauth)
    internalconnection = API.connect(connstr, extraauth)
    return Connection(internalconnection, dsn)
end

# back compat.
# TODO: docstring for this?
Connection(dsn::AbstractString, usr, pwd) = Connection(dsn; user=usr, password=pwd)

"""
    DBInterface.connect(ODBC.Connection, dsn_or_connectionstring; user, password, extraauth, connectionstring::Bool=false)

Construct a `Connection` type by connecting to a valid ODBC Connection or by specifying a datasource name or valid connection string.
1st argument `dsn` can be either the name of a pre-defined ODBC Connection or a valid connection string.
A great resource for building valid connection strings is [http://www.connectionstrings.com/](http://www.connectionstrings.com/).
Takes optional keyword arguments `username`, `password`, and `extraauth`, which are used to specify auth parameters. `extraauth` is
to allow you to pass a sensitive string to be appended verbatim to the end of the connection string, e.g. DB-specific auth token
parameters.

Note that connecting will use the currently "set" ODBC driver manager, which by default is iODBC on OSX, unixODBC on Linux, and
the system driver manager on Windows. If you experience cryptic connection errors, it's probably worth checking with your ODBC
driver documentation to see if it requires a specific driver manager. For example, Microsoft-provided ODBC driver for SQL Server
requires unixODBC on OSX, but by default, ODBC.jl sets the driver manager to iODBC, so before connecting, you would need to do:
```julia
ODBC.setunixODBC()
conn = ODBC.Connection(...)
```
"""
DBInterface.connect(::Type{Connection}, args...; kw...) = Connection(args...; kw...)

Base.isopen(c::Connection) = c.dbc.ptr != C_NULL && API.getconnectattr(c.dbc, API.SQL_ATTR_CONNECTION_DEAD) == API.SQL_CD_FALSE

"disconnect a connected `Connection`"
function disconnect!(conn::Connection)
    # for #292, it seems we need to finalize any stmts on the connection
    # before disconnect/freehandle, even though disconnect should do that for us
    for stmt in keys(conn.stmts)
        finalize(stmt)
    end
    API.disconnect(conn.dbc)
    return nothing
end

"""
    DBInterface.close!(conn)

Close an open connection. In general, statements and open cursors will not be valid
once a connection has been closed.
"""
DBInterface.close!(dsn::Connection) = disconnect!(dsn)

"Struct for working with prepared statements and parameter binding; see `DBInterface.prepare` and `DBInterface.execute` for more details"
mutable struct Statement <: DBInterface.Statement
    dsn::Connection
    stmt::API.Handle
    sql::String
    bindings::Union{Nothing, Vector{Binding}}
    nparams::Int
end

"""
    DBInterface.getconnection(stmt)

Return the connection for the given statement. Part of the required interface.
"""
DBInterface.getconnection(stmt::Statement) = stmt.dsn

"""
    DBInterface.close!(stmt)

Close a prepared statement. Further parameter binding or execution will not be valid.
"""
DBInterface.close!(stmt::Statement) = finalize(stmt.stmt)

"""
    DBInterface.prepare(conn, sql) -> ODBC.Statement

Prepare a query string, optionally including parameters to bind upon execution (with `?` markers).
Please refer to individual dbms documentation for the exact level of parameter binding support.

The returned prepared statement can then be passed to `DBInterface.execute(stmt, params)` with
`params` that will be bound before execution. This allows preparing the statement once,
and re-using it many times with different parameters (or the same) efficiently.
"""
function DBInterface.prepare(conn::Connection, sql::AbstractString)
    clear!(conn)
    stmt = API.prepare(conn.dbc, sql)
    conn.stmts[stmt] = 0
    return Statement(conn, stmt, sql, nothing, API.numparams(stmt))
end

@noinline paramcheck(stmt, params) = (stmt.nparams == 0 || length(params) == stmt.nparams) || error("stmt requires $(stmt.nparams) params, only $(length(params)) provided")

"""
    DBInterface.execute(stmt, params=(); iterate_rows::Bool=false, ignore_driver_row_count::Bool=false, normalizenames::Bool=false, debug::Bool=false) -> ODBC.Cursor

Execute a prepare statement, binding any parameters beforehand. Returns a `Cursor`
object, even if the statement is not resultset-producing (cursor will have zero rows and/or columns).
The `Cursor` object satisfies the [Tables.jl](https://juliadata.github.io/Tables.jl/dev/)
interface as a source, so any valid sink can be used for inspecting results (a list of integrations
is maintained [here](https://github.com/JuliaData/Tables.jl/blob/master/INTEGRATIONS.md)).

Supported keyword arguments include:
  * `iterate_rows::Bool`: for forcing row iteration of the resultset
  * `ignore_driver_row_count::Bool`: for ignoring the row count returned from the database driver; in some cases (Netezza), the driver may return an incorrect or "prefetched" number for the row count instead of the actual row count; this allows ignoring those numbers and fetching the resultset until truly exhausted
  * `normalizenames::Bool`: normalize column names to valid Julia identifiers; this can be convenient when working with the results in, for example, a `DataFrame` where you can access columns like `df.col1`
  * `debug::Bool`: for printing additional debug information during the query/result process.
"""
function DBInterface.execute(stmt::Statement, params=(); debug::Bool=false, kw...)
    API.freestmt(stmt.stmt)
    clear!(stmt.dsn)
    paramcheck(stmt, params)
    stmt.dsn.cursorstmt = stmt.stmt
    stmt.bindings = bindparams(stmt.stmt, params, stmt.bindings)
    debug && println("executing prepared statement: $(stmt.sql)")
    API.execute(stmt.stmt)
    c = Cursor(stmt.stmt; debug=debug, kw...)
    return c
end

"""
    DBInterface.execute(conn, sql, params=(); iterate_rows::Bool=false, ignore_driver_row_count::Bool=false, normalizenames::Bool=false, debug::Bool=false) -> ODBC.Cursor

Send a query directly to connection for execution. Returns a `Cursor`
object, even if the statement is not resultset-producing (cursor will have zero rows and/or columns).
The `Cursor` object satisfies the [Tables.jl](https://juliadata.github.io/Tables.jl/dev/)
interface as a source, so any valid sink can be used for inspecting results (a list of integrations
is maintained [here](https://github.com/JuliaData/Tables.jl/blob/master/INTEGRATIONS.md)).

Supported keyword arguments include:
  * `iterate_rows::Bool`: for forcing row iteration of the resultset
  * `ignore_driver_row_count::Bool`: for ignoring the row count returned from the database driver; in some cases (Netezza), the driver may return an incorrect or "prefetched" number for the row count instead of the actual row count; this allows ignoring those numbers and fetching the resultset until truly exhausted
  * `normalizenames::Bool`: normalize column names to valid Julia identifiers; this can be convenient when working with the results in, for example, a `DataFrame` where you can access columns like `df.col1`
  * `debug::Bool`: for printing additional debug information during the query/result process.

This is an alternative execution path to `DBInterface.execute` with a prepared statement.
This method is faster/less overhead for one-time executions, but prepared statements will
have more benefit for repeated executions (even with different parameters).
"""
function DBInterface.execute(conn::Connection, sql::AbstractString, params=(); debug::Bool=false, kw...)
    clear!(conn)
    stmt = API.Handle(API.SQL_HANDLE_STMT, API.getptr(conn.dbc))
    conn.stmts[stmt] = 0
    conn.cursorstmt = stmt
    API.enableasync(stmt)
    bindings = bindparams(stmt, params, nothing)
    debug && println("executing statement: $sql")
    GC.@preserve bindings (API.execdirect(stmt, sql))
    return Cursor(stmt; debug=debug, kw...)
end

mutable struct Cursor{columnar, knownlength}
    stmt::API.Handle
    rows::Int
    cols::Int
    names::Vector{Symbol}
    types::Vector{Type}
    lookup::Dict{Symbol, Int}
    current_rownumber::Int
    current_resultsetnumber::Int
    bindings::Vector{Binding}
    columns::Vector{AbstractVector}
    metadata::Any
end

# takes a recently executed statement handle and handles any produced resultsets
function Cursor(stmt; iterate_rows::Bool=false, ignore_driver_row_count::Bool=false, normalizenames::Bool=false, debug::Bool=false)
    rows = API.numrows(stmt)
    cols = API.numcols(stmt)
    debug && println("rows = $rows, cols = $cols")
    # Allocate arrays to hold each column's metadata
    names = Vector{Symbol}(undef, cols)
    types = Vector{Type}(undef, cols)
    namelengths = Vector{API.SQLSMALLINT}(undef, cols)
    sqltypes = Vector{API.SQLSMALLINT}(undef, cols)
    ctypes = Vector{API.SQLSMALLINT}(undef, cols)
    columnsizes = Vector{API.SQLULEN}(undef, cols)
    decimaldigits = Vector{API.SQLSMALLINT}(undef, cols)
    nullables = Vector{API.SQLSMALLINT}(undef, cols)
    longtexts = Vector{Bool}(undef, cols)
    cname = Vector{API.sqlwcharsize()}(undef, 1024)
    for i = 1:cols
        API.SQLDescribeCol(API.getptr(stmt), i, cname, namelengths, sqltypes, columnsizes, decimaldigits, nullables)
        nm = API.str(cname, namelengths[i])
        names[i] = normalizenames ? normalizename(nm) : Symbol(nm)
        sqltype = sqltypes[i]
        ctype, jltype = fetchtypes(sqltype, columnsizes[i])
        ctypes[i] = ctype
        types[i] = nullables[i] == API.SQL_NO_NULLS ? jltype : Union{Missing, jltype}
        # Some drivers return 0 size for variable length or large fields
        longtexts[i] = (sqltype == API.SQL_LONGVARCHAR || sqltype == API.SQL_LONGVARBINARY || sqltype == API.SQL_WLONGVARCHAR) || (columnsizes[i] == 0 && sqltype in (API.SQL_VARCHAR, API.SQL_WVARCHAR, API.SQL_VARBINARY))
        if ctype == API.SQL_C_CHAR || ctype == API.SQL_C_WCHAR || ctype == API.SQL_C_BINARY
            if longtexts[i] || columnsizes[i] == 0 || columnsizes[i] > 2^22
                longtexts[i] = true
                columnsizes[i] = 255
            end
            columnsizes[i] += 1
        end
    end
    metadata = [Any["column name", names...] Any["column type", types...] Any["sql type", map(x->API.SQL_TYPES[x], sqltypes)...] Any["c type", map(x->API.C_TYPES[x], ctypes)...] Any["sizes", map(Int, columnsizes)...] Any["nullable", map(x->x != API.SQL_NO_NULLS, nullables)...] Any["long data", longtexts...]]
    columnar = knownlength = true
    if any(longtexts) || rows <= 0 || iterate_rows || ignore_driver_row_count
        rowset = 1
        columnar = false
        knownlength = rows > 0 && !ignore_driver_row_count
    else
        rowset = rows
    end
    debug && println("columnar = $columnar, rowset = $rowset")
    API.setrowset(stmt, rowset)
    # we need bindings regardless of row vs. column fetching
    bindings = getbindings(stmt, columnar, ctypes, sqltypes, columnsizes, nullables, longtexts, rowset)
    if columnar && cols > 0
        # will be populated by call to SQLFetchScroll
        rowsfetchedref = API.setrowsfetched(stmt)
        API.fetch(stmt)
        rowsfetched = rowsfetchedref[]
        debug && @show rowsfetched
        columns = Vector{AbstractVector}(undef, cols)
        for (i, binding) in enumerate(bindings)
            ctype = binding.valuetype
            if ctype == API.SQL_C_CHAR || ctype == API.SQL_C_WCHAR || ctype == API.SQL_C_BINARY
                T = types[i]
                A = Vector{T}(undef, rowsfetched)
                data = binding.value.buffer::Vector{UInt8}
                inds = binding.strlen_or_indptr
                cur = 1
                elsize = columnsizes[i]
                for j = 1:rowsfetched
                    @inbounds ind = inds[j]
                    A[j] = ind == API.SQL_NULL_DATA ? missing : jlcast(Base.nonmissingtype(T), unsafe_wrap(Array, pointer(data, cur), ind))
                    cur += elsize
                end
                columns[i] = A
            elseif ctype == API.SQL_C_TYPE_DATE || ctype == API.SQL_C_TYPE_TIME || ctype == API.SQL_C_TYPE_TIMESTAMP
                specialize(binding.value.buffer) do data
                    T = types[i]
                    A = Vector{T}(undef, rowsfetched)
                    inds = binding.strlen_or_indptr
                    @simd for j = 1:rowsfetched
                        @inbounds A[j] = ifelse(inds[j] == API.SQL_NULL_DATA, missing, Base.nonmissingtype(T)(data[j]))
                    end
                    columns[i] = A
                end
            else
                if nullables[i] == API.SQL_NO_NULLS
                    columns[i] = copy(binding.value.buffer)
                else
                    specialize(binding.value.buffer) do A
                        inds = binding.strlen_or_indptr
                        @simd for j = 1:rowsfetched
                            @inbounds A[j] = ifelse(inds[j] == API.SQL_NULL_DATA, missing, A[j])
                        end
                        columns[i] = A
                    end
                end
            end
        end
    else
        columns = AbstractVector[]
    end
    lookup = Dict(nm => i for (i, nm) in enumerate(names))
    return Cursor{columnar, knownlength}(stmt, rows, cols, names, types, lookup, 0, 1, bindings, columns, metadata)
end

"""
    DBInterface.transaction(f, conn::ODBC.Connection)

Open a transaction against an ODBC Connection `conn`, execute a closure `f`,
then "commit" the transaction after executing the closure function. Used in
`DBInterface.executemany` to wrap the individual execute calls in a transaction
since this often leads to much better performance in database systems.
"""
DBInterface.transaction(f, conn::Connection) = transaction(f, conn)

# Tables.jl interface
Tables.istable(::Type{<:Cursor}) = true
Tables.schema(x::Cursor) = Tables.Schema(x.names, x.types)

# columnar source
Tables.columnaccess(::Type{Cursor{true, T}}) where {T} = true
Tables.columns(x::Cursor{true}) = x

Tables.columnnames(x::Cursor{true}) = x.names
Tables.getcolumn(x::Cursor{true}, nm::Symbol) = Tables.getcolumn(x, x.lookup[nm])
Tables.getcolumn(x::Cursor{true}, i::Int) = x.columns[i]

# row source
Tables.rowaccess(::Type{Cursor{false, T}}) where {T} = true
Tables.rows(x::Cursor{false}) = x

struct Row <: Tables.AbstractRow
    cursor::Cursor
    rownumber::Int
    resultsetnumber::Int
end

getcursor(x::Row) = getfield(x, :cursor)
getrownumber(x::Row) = getfield(x, :rownumber)
getresultsetnumber(x::Row) = getfield(x, :resultsetnumber)

Tables.columnnames(x::Row) = getfield(x, :cursor).names

@noinline wrongrow(i) = throw(ArgumentError("row $i is no longer valid; odbc results are forward-only iterators where each row is only valid when iterated"))

Tables.getcolumn(x::Row, nm::Symbol) = Tables.getcolumn(x, getcursor(x).lookup[nm])
Tables.getcolumn(x::Row, i::Int) = Tables.getcolumn(x, getcursor(x).types[i], i, getcursor(x).names[i])

function Tables.getcolumn(x::Row, ::Type{T}, i::Int, nm::Symbol) where {T}
    c = getcursor(x)
    (getrownumber(x) == c.current_rownumber && getresultsetnumber(x) == c.current_resultsetnumber) || wrongrow(getrownumber(x))
    b = c.bindings[i]
    if T >: Missing && b.strlen_or_indptr[1] == API.SQL_NULL_DATA
        return missing
    elseif b.valuetype == API.SQL_C_CHAR || b.valuetype == API.SQL_C_WCHAR || b.valuetype == API.SQL_C_BINARY
        data = b.value.buffer::Vector{UInt8}
        bytes = data[1:b.totallen]
        return jlcast(Base.nonmissingtype(T), bytes)
    elseif b.valuetype == API.SQL_C_TYPE_DATE || b.valuetype == API.SQL_C_TYPE_TIME || b.valuetype == API.SQL_C_TYPE_TIMESTAMP
        return specialize(x -> Base.nonmissingtype(T)(x[1]), b.value.buffer)
    else
        return specialize(x -> x[1], b.value.buffer)
    end
end

Base.IteratorSize(::Type{Cursor{false, knownlength}}) where {knownlength} = knownlength ? Base.HasLength() : Base.SizeUnknown()
Base.length(x::Cursor{false, true}) = x.rows
Base.IteratorEltype(::Type{Cursor{false, knownlength}}) where {knownlength} = Base.HasEltype()
Base.eltype(x::Cursor{false, knownlength}) where {knownlength} = Row

function Base.iterate(x::Cursor{false}, st=1)
    status = API.SQLFetchScroll(API.getptr(x.stmt), API.SQL_FETCH_NEXT, 0)
    while status == API.SQL_STILL_EXECUTING
        status = API.SQLFetchScroll(API.getptr(x.stmt), API.SQL_FETCH_NEXT, 0)
    end

    # iteration end
    status == API.SQL_NO_DATA           && return nothing
    status == API.SQL_NTS               && return nothing

    # errors
    status == API.SQL_ERROR             && error(API.diagnostics(x.stmt))
    status == API.SQL_INVALID_HANDLE    && error(API.diagnostics(x.stmt))
    
    # continue
    status == API.SQL_SUCCESS_WITH_INFO && @warn(API.diagnostics(x.stmt))

    x.current_rownumber = st
    for (i, binding) in enumerate(x.bindings)
        getdata(x.stmt, i, binding)
    end
    return Row(x, st, x.current_resultsetnumber), st + 1
end

# support returning multiple results from single execute calls
mutable struct Cursors
    cursor::Cursor
    kw
end

Base.eltype(c::Cursors) = Cursor
Base.IteratorSize(::Type{<:Cursors}) = Base.SizeUnknown()

function Base.iterate(cursors::Cursors, first=true)
    cursors.cursor.stmt.ptr == C_NULL && return nothing
    if !first
        if API.moreresults(cursors.cursor.stmt) == API.SQL_SUCCESS
            cursors.cursor = Cursor(cursors.cursor.stmt; cursors.kw...)
        else
            return nothing
        end
    end
    return cursors.cursor, false
end

DBInterface.executemultiple(conn::Connection, sql::AbstractString, params=(); kw...) =
    Cursors(DBInterface.execute(conn, sql, params; kw...), kw)
