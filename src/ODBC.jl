module ODBC

#Requires DataFrames
#require("DataFrames")
using DataFrames

export connect, advancedconnect, query, querymeta, Connection, Metadata, conn, Connections, disconnect, drivers, datasources

import Base.show

include("consts.jl")

#Connection object that holds information related to each established connection and retrieved result sets
type Connection
	dsn::String
	number::Int
	dbc_ptr::Ptr{Void}
	stmt_ptr::Ptr{Void}
	resultset::DataFrame
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
		println("Statment pointer: $(conn.stmt_ptr)")
		if isequal(conn.resultset,null_resultset)
		print("Contains resultset? No")
		else
		print("Contains resultset? Yes (access by referencing [connection].results)")
		end
	end
end
#Metadata type holds metadata related to an executed query resultset
type Metadata
	querystring::String
	cols::Int
	rows::Int
	colnames::Array{ASCIIString}
	coltypes::Array{Int16}
	colsizes::Array{Int}
	coldigits::Array{Int16}
	colnulls::Array{Int16}
end
function show(io::IO,meta::Metadata)
	if meta == null_meta
		print("No metadata")
	else
		println("Resultset metadata on executed query")
		println("------------------------------------")
		println("Columns: $(meta.cols)")
		println("Rows: $(meta.rows)")
		println("Column Names: $(meta.colnames)")
		println("Column Types: $(meta.coltypes)")
		println("Column Sizes: $(meta.colsizes)")
		println("Column Digits: $(meta.coldigits)")
		println("Column Nullable: $(meta.colnulls)")
	end
end

#Global module Variables
env = C_NULL
Connections = ref(Connection)
number_of_connections = 0
const null_resultset = DataFrame(0)
const null_connection = Connection("",0,C_NULL,C_NULL,null_resultset)
const null_meta = Metadata("",0,0,ref(ASCIIString),ref(Int16),ref(Int),ref(Int16),ref(Int16))
conn = null_connection #Create null default connection
rowset = 1

#I was running into some errors on Linux about not being able to import Base.c_malloc, so I've redefined them here for now
c_free(p::Ptr) = ccall(:free, Void, (Ptr{Void},), p)
c_malloc(size::Int) = ccall(:malloc, Ptr{Void}, (Int,), size)

include("backend.jl")
##############################################################################
#User-facing functions
include("userfacing.jl")

end #ODBC module
