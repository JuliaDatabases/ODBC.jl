module ODBC

using Compat, NullableArrays

if VERSION < v"0.4-"
    using Dates
end

include("ODBC_Types.jl")
include("ODBC_API.jl")

# Holds metadata related to an executed query resultset
immutable Metadata
    querystring::AbstractString
    cols::Int
    rows::Int
    colnames::Array{UTF8String}
    coltypes::Array{Int16}
    colsizes::Array{Int}
    coldigits::Array{Int16}
    colnulls::Array{Int16}
end

Base.show(io::IO,meta::Metadata) = begin
    println(io, "Resultset metadata for executed query")
    println(io, "-------------------------------------")
    println(io, "Query:   $(meta.querystring)")
    println(io, "Columns: $(meta.cols)")
    println(io, "Rows:    $(meta.rows)")
    println(io, [meta.colnames;
                 meta.coltypes;
                 map(x->get(SQL_TYPES, Int(x), "SQL_CHAR"),meta.coltypes);
                 map(x->get(C_TYPES, Int(x), "SQL_C_CHAR"),meta.coltypes);
                 map(x->get(SQL2Julia, Int(x), UInt8),meta.coltypes);
                 meta.colsizes;
                 meta.coldigits;
                 meta.colnulls])
end

# Connection object holds information related to each
# established connection and retrieved resultsets
type Connection
    dsn::AbstractString
    dbc_ptr::Ptr{Void}
    stmt_ptr::Ptr{Void}

    # Holding a reference to the last resultset is useful if the user
    # runs several test queries just using `query()` or `sql"..."` and
    # then realizes the last resultset should actually be saved to a variable.
    resultset::Any
end

Base.show(io::IO,conn::Connection) = print(io,"ODBC.Connection($(conn.dsn))")

include("backend.jl")
include("userfacing.jl")

function __init__()
    global const ENV = ODBC.ODBCAllocHandle(ODBC.SQL_HANDLE_ENV, ODBC.SQL_NULL_HANDLE)
end

end #ODBC module
