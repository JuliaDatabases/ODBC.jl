function quoteid(conn, str)
    if conn.quoteidentifierchar == '\0'
        conn.quoteidentifierchar = API.getinfostring(conn.dbc, API.SQL_IDENTIFIER_QUOTE_CHAR)[1]
    end
    # avoid double quoting
    if str[1] == conn.quoteidentifierchar && str[end] == conn.quoteidentifierchar
        return str
    else
        return string(conn.quoteidentifierchar, str, conn.quoteidentifierchar)
    end
end

sqltype(conn, ::Type{Union{T, Missing}}) where {T} = sqltype(conn, T)

function sqltype(conn, T)
    if isempty(conn.types)
        types = Tables.columntable(Cursor(API.gettypes(conn.dbc)))
        conn.alltypes = types
        i = findfirst(==(API.SQL_VARCHAR), types.DATA_TYPE)
        if i === nothing
            defaultT = "VARCHAR(255)"
        else
            defaultT = types.TYPE_NAME[i] * "($(types.COLUMN_SIZE[i]))"
        end
        for jlT in BINDTYPES
            _, sqlT = bindtypes(jlT)
            i = findfirst(==(sqlT), types.DATA_TYPE)
            nm = i !== nothing ? types.TYPE_NAME[i] : defaultT
            if i !== nothing && types.CREATE_PARAMS[i] !== missing && nm != "DOUBLE" && nm != "FLOAT"
                nm *= occursin(',', types.CREATE_PARAMS[i]) ? "($(typeprecision(jlT)),$(typescale(jlT)))" : "($(types.COLUMN_SIZE[i]))"
            end
            conn.types[jlT] = nm
        end
    end
    return conn.types[T]
end

checkdupnames(names) = length(unique(map(x->lowercase(String(x)), names))) == length(names) || error("duplicate case-insensitive column names detected; sqlite doesn't allow duplicate column names and treats them case insensitive")

function createtable(conn::Connection, nm::AbstractString, sch::Tables.Schema; debug::Bool=false, quoteidentifiers::Bool=true, createtableclause::AbstractString="CREATE TABLE")
    names = sch.names
    checkdupnames(names)
    types = [sqltype(conn, T) for T in sch.types]
    columns = (string(quoteidentifiers ? quoteid(conn, String(names[i])) : names[i], ' ', types[i]) for i = 1:length(names))
    debug && @info "executing create table statement: `$createtableclause $nm ($(join(columns, ", ")))`"
    return DBInterface.execute(conn, "$createtableclause $nm ($(join(columns, ", ")))")
end

load(conn::Connection, table::AbstractString="odbcjl_"*Random.randstring(5); kw...) = x->load(x, conn, table; kw...)

function load(itr, conn::Connection, name::AbstractString="odbcjl_"*Random.randstring(5); append::Bool=true, quoteidentifiers::Bool=true, debug::Bool=true, kw...)
    # get data
    rows = Tables.rows(itr)
    sch = Tables.schema(rows)
    if sch === nothing
        # we want to ensure we always have a schema, so materialize if needed
        rows = Tables.rows(columntable(rows))
        sch = Tables.schema(rows)
    end
    # ensure table exists
    if quoteidentifiers
        name = quoteid(conn, name)
    end
    try
        createtable(conn, name, sch; quoteidentifiers=quoteidentifiers, debug=debug, kw...)
    catch e
        @warn "error creating table" (e, catch_backtrace())
    end
    if !append
        DBInterface.execute(conn, "DELETE FROM $name")
    end
    # start a transaction for inserting rows
    transaction(conn) do
        params = chop(repeat("?,", length(sch.names)))
        stmt = DBInterface.prepare(conn, "INSERT INTO $name VALUES ($params)")
        for (i, row) in enumerate(rows)
            debug && @info "inserting row $i; $(Tables.Row(row))"
            DBInterface.execute(stmt, Tables.Row(row); debug=debug)
        end
    end

    return name
end

function transaction(f::Function, conn)
    API.setcommitmode(conn.dbc, false)
    try
        f()
        API.endtran(conn.dbc, true)
    catch
        API.endtran(conn.dbc, false)
        rethrow()
    finally
        API.setcommitmode(conn.dbc, true)
    end
end