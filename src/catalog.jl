# Catalog functions.

"""
    tables(conn; catalogname=nothing, schemaname=nothing, tablename=nothing, tabletype=nothing) -> ODBC.Cursor

Find tables by the given criteria.  This function returns a `Cursor` object that
produces one row per matching table.

Search criteria include:
  * `catalogname`: search pattern for catalog names
  * `schemaname`: search pattern for schema names
  * `tablename`: search pattern for table names
  * `tabletypes`: comma-separated list of table types

A search pattern may contain an underscore (`_`) to represent any single character
and a percent sign (`%`) to represent any sequence of zero or more characters.
Use an escape character (driver-specific, but usually `\\`) to include underscores,
percent signs, and escape characters as literals.
"""
function tables(conn; catalogname=nothing, schemaname=nothing, tablename=nothing, tabletype=nothing)
    clear!(conn)
    stmt = API.Handle(API.SQL_HANDLE_STMT, API.getptr(conn.dbc))
    conn.stmts[stmt] = 0
    conn.cursorstmt = stmt
    API.enableasync(stmt)
    API.tables(stmt, catalogname, schemaname, tablename, tabletype)
    return Cursor(stmt)
end

"""
    columns(conn; catalogname=nothing, schemaname=nothing, tablename=nothing, columnname=nothing) -> ODBC.Cursor

Find columns by the given criteria.  This function returns a `Cursor` object that
produces one row per matching column.

Search criteria include:
  * `catalogname`: name of the catalog
  * `schemaname`: search pattern for schema names
  * `tablename`: search pattern for table names
  * `columnname`: search pattern for column names

A search pattern may contain an underscore (`_`) to represent any single character
and a percent sign (`%`) to represent any sequence of zero or more characters.
Use an escape character (driver-specific, but usually `\\`) to include underscores,
percent signs, and escape characters as literals.
"""
function columns(conn; catalogname=nothing, schemaname=nothing, tablename=nothing, columnname=nothing)
    clear!(conn)
    stmt = API.Handle(API.SQL_HANDLE_STMT, API.getptr(conn.dbc))
    conn.stmts[stmt] = 0
    conn.cursorstmt = stmt
    API.enableasync(stmt)
    API.columns(stmt, catalogname, schemaname, tablename, columnname)
    return Cursor(stmt)
end
