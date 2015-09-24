using DataFrames
using ODBC
con = ODBC.connect("Default")
function check_API_query(q)
  a = ODBC.query(q)
  #show isdefined(:a)
  if (typeof(a) == DataFrame)
    println("API query passed")
  else
    println("API query failed")
  end
end
function check_API_querymeta(q)
  a = ODBC.querymeta(q)
  #show isdefined(:a)
  if (typeof(a) == Metadata)
    println("API querymeta passed")
  else
    println("API querymeta failed")
  end
end
q = "show tables;"
check_API_query(q)
check_API_querymeta(q)
listdsns()
listdrivers()
ODBC.disconnect(con)
