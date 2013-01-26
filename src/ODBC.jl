module ODBC

#Requires DataFrames
require("DataFrames")
using DataFrames

export Connect, AdvancedConnect, Query, Connection, conn, Connections, resultset, Disconnect, ListDrivers, ListDatasources

include("consts.jl")

#Connection object that holds information related to each established connection and retrieved result sets
type Connection
	dsn::String
	number::Int
	dbc_ptr::Ptr{Void}
	stmt_ptr::Ptr{Void}
	resultset::DataFrame
end
function show(io,conn::Connection)
	if conn == null_connection
		print("Null ODBC Connection Object")
	else
		println("ODBC Connection Object")
		println("----------------------")
		println("Connection Data Source: $(conn.dsn)")
		println("$(conn.dsn) Connection Number: $(conn.number)")
		println("Connection pointer: $(conn.dbc_ptr)")
		println("Statment pointer: $(conn.stmt_ptr)")
		if conn.results == 0
		print("Contains resultset? No")
		else
		print("Contains resultset? Yes (access by referencing connection.results)")
		end
	end
end

#Global module Variables
env = C_NULL
Connections = ref(Connection)
number_of_connections = 0
const null_resultset = DataFrame(0)
const null_connection = Connection("",0,C_NULL,C_NULL,null_resultset)
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
