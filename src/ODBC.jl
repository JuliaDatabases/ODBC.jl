module ODBC

using DataFrames
using Datetime
using UTF16

export advancedconnect, query, querymeta, @sql_str, Connection, Metadata, conn, Connections, disconnect, listdrivers, listdsns

import Base: show, Chars, string

include("ODBC_Types.jl")
include("ODBC_API.jl")

#Metadata type holds metadata related to an executed query resultset
type Metadata
	querystring::String
	cols::Int
	rows::Int
	colnames::Array{UTF8String}
	coltypes::Array{(String,Int16)}
	colsizes::Array{Int}
	coldigits::Array{Int16}
	colnulls::Array{Int16}
end
function show(io::IO,meta::Metadata)
	if meta == null_meta
		print(io,"No metadata")
	else
		println(io,"Resultset metadata for executed query")
		println(io,"------------------------------------")
		println(io,"Columns: $(meta.cols)")
		println(io,"Rows: $(meta.rows)")
		println(io,"Column Names: $(meta.colnames)")
		println(io,"Column Types: $(meta.coltypes)")
		println(io,"Column Sizes: $(meta.colsizes)")
		println(io,"Column Digits: $(meta.coldigits)")
		println(io,"Column Nullable: $(meta.colnulls)")
		print(io,"Query: $(meta.querystring)")
	end 
end
#Connection object that holds information related to each established connection and retrieved resultsets
type Connection
	dsn::String
	number::Int
	dbc_ptr::Ptr{Void}
	stmt_ptr::Ptr{Void}
	#Holding a reference to the last resultset is useful if the user runs several test queries just using `query()` or `sql"..."`
	#then realizes the last resultset should actually be saved to a variable (happended to me all the time in RODBC)
	resultset::Any
end
function show(io::IO,conn::Connection)
	if conn == null_connection
		print("Null ODBC Connection Object")
	else
		println("ODBC Connection Object")
		println("----------------------")
		println("Connection Data Source: $(conn.dsn)")
		println("$(conn.dsn) Connection Number: $(conn.number)")
		println("Connection pointer: $(conn.dbc_ptr)")
		println("Statement pointer: $(conn.stmt_ptr)")
		if isequal(conn.resultset,null_resultset)
			print("Contains resultset? No")
		else
			print("Contains resultset(s)? Yes (access by referencing the resultset field (e.g. conn.resultset))")
		end
	end
end
#There was a weird bug where Connections was showing each Connection 3 times, this seems to solve it
show(io::IO,conns::Array{Connection,1}) = map(show,conns)

typealias Output{T <: String} Union(Symbol,T,Array{T,1})
#Global module consts and variables
const null_resultset = DataFrame(0)
const null_connection = Connection("",0,C_NULL,C_NULL,null_resultset)
const null_meta = Metadata("",0,0,ref(ASCIIString),Array((String,Int16),0),ref(Int),ref(Int16),ref(Int16))
env = C_NULL
Connections = ref(Connection) #For managing references to multiple connections
conn = null_connection #Create default connection = null
ret = ""

include("backend.jl")
include("userfacing.jl")

end #ODBC module
