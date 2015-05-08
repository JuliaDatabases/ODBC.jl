module ODBC

using Compat
using DataFrames
using DataArrays
if VERSION < v"0.4-"
    using Dates
end

export advancedconnect,
       query, querymeta, @query, @sql_str,
       Connection, Metadata, conn, Connections,
       disconnect, listdrivers, listdsns

include("ODBC_Types.jl")
include("ODBC_API.jl")

# Holds metadata related to an executed query resultset
type Metadata
    querystring::String
    cols::Int
    rows::Int
    colnames::Array{UTF8String}
    @compat coltypes::Array{Tuple{String, Int16}}
    colsizes::Array{Int}
    coldigits::Array{Int16}
    colnulls::Array{Int16}
end

Base.show(io::IO,meta::Metadata) = begin
    if meta == null_meta
        print(io, "No metadata")
    else
        println(io, "Resultset metadata for executed query")
        println(io, "-------------------------------------")
        println(io, "Query:   $(meta.querystring)")
        println(io, "Columns: $(meta.cols)")
        println(io, "Rows:    $(meta.rows)")
        println(io, DataFrame(Names=meta.colnames,
                              Types=meta.coltypes,
                              Sizes=meta.colsizes,
                              Digits=meta.coldigits,
                              Nullable=meta.colnulls))
    end
end

# Connection object holds information related to each
# established connection and retrieved resultsets
type Connection
    dsn::String
    number::Int
    dbc_ptr::Ptr{Void}
    stmt_ptr::Ptr{Void}

    # Holding a reference to the last resultset is useful if the user
    # runs several test queries just using `query()` or `sql"..."` and
    # then realizes the last resultset should actually be saved to a variable.
    resultset::Any
end

Base.show(io::IO,conn::Connection) = begin
    if conn == null_conn
        print(io, "Null ODBC Connection Object")
    else
        println(io, "ODBC Connection Object")
        println(io, "----------------------")
        println(io, "Connection Data Source: $(conn.dsn)")
        println(io, "$(conn.dsn) Connection Number: $(conn.number)")
        if conn.resultset == null_resultset
            print(io, "Contains resultset(s)? No")
        else
            print(io, "Contains resultset(s)? Yes")
        end
    end
end

Base.show(io::IO, conns::Vector{Connection}) = map(show, conns)

# Global module consts and variables
typealias Output Union(DataType,String)

const null_resultset = DataFrame()
const null_conn = Connection("", 0, C_NULL, C_NULL, null_resultset)
@compat const null_meta = Metadata("", 0, 0, UTF8String[], Tuple{String,Int16}[], Int[], Int16[], Int16[])

global env = C_NULL

# For managing references to multiple connections
global Connections = Connection[]

#Create default connection = null
global conn = null_conn
global ret = ""

include("backend.jl")
include("userfacing.jl")

end #ODBC module
