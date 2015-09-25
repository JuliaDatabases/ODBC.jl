using DataFrames
using ODBC
con = ODBC.connect("Default")
global Query_passed = 0
global Query_failed = 0
global Query_Error = 0

function check_API_query(q)
  global Query_passed
  global Query_failed
  global Query_Error
  try
    a = ODBC.query(q)
    if (typeof(a) == DataFrame)
      Query_passed = Query_passed + 1
      println("API query <$q> passed")
    else
      println("API query <$q> failed")
      Query_failed = Query_failed + 1
    end
  catch
    println("\nQuery \n<$q>\n is generating an error, please revise your query\n")
    Query_Error = Query_Error + 1
    return
  end
end

function check_API_querymeta(q)
  global Query_passed
  global Query_failed
  global Query_Error
  try
    a = ODBC.querymeta(q)
    if (typeof(a) == Metadata)
      println("API querymeta <$q> passed")
      Query_passed = Query_passed + 1
    else
      println("API querymeta <$q> failed")
      Query_failed = Query_failed + 1
    end
  catch
    println("\nQuery \n<$q>\n is generating an error, please revise your query\n")
    Query_Error = Query_Error + 1
    return
  end
end
# Multi Statement is not supported by this wrapper, a multi-statement has been intentionally added
#q = ["show databases;", "use dbtest;", "show tables;", "select * from employee;", "select count(*) from employee;", "show columns from employee;", "select id from employee group by id;", "select * from employee where mid = -1;","select count(*) from employee where mid = 0;", "select * from employee where mid = 2 limit 20;","select count(*) from employee; select count(*) from employee;","select a.id, b.id from employee a left outer join employee b on a.id = b.id where a.mid = 2 and b.mid = 0;"]
q = ["show databases;", "use mysqltest1;", "show tables;", "select * from Employee;", "select count(*) from Employee;", "show columns from Employee;", "select ID from Employee group by ID;", "select * from Employee where Salary = -1;","select count(*) from Employee where OfficeNo > 0;", "select * from Employee where OfficeNo > 2 limit 2;","select count(*) from Employee; select count(*) from Employee;","select a.ID, b.ID from Employee a left outer join Employee b on a.ID = b.ID where a.OfficeNo > 2 and b.OfficeNo < 45;"]
create_q = ["CREATE DATABASE mysqltest1;","CREATE USER test1 IDENTIFIED BY 'test1';","GRANT ALL ON mysqltest1.* TO test1;","use mysqltest1","CREATE TABLE Employee(ID INT NOT NULL AUTO_INCREMENT,Name VARCHAR(255),Salary FLOAT,JoinDate DATE,LastLogin DATETIME,LunchTime TIME,OfficeNo TINYINT,JobType ENUM('HR', 'Management', 'Accounts'),Senior BIT(1),empno SMALLINT,PRIMARY KEY (ID));","INSERT INTO Employee (Name, Salary, JoinDate, LastLogin, LunchTime, OfficeNo, JobType, Senior, empno) VALUES ('John', 10000.50, '2015-8-3', '2015-9-5 12:31:30', '12:00:00', 1, 'HR', b'1', 1301), ('Tom', 20000.25, '2015-8-4', '2015-10-12 13:12:14', '13:00:00', 12, 'HR', b'1', 1422), ('Jim', 30000.00, '2015-6-2', '2015-9-5 10:05:10', '12:30:00', 45, 'Management', b'0', 1567), ('Tim', 15000.50, '2015-7-25', '2015-10-10 12:12:25', '12:30:00', 56, 'Accounts', b'1', 3200);","UPDATE Employee SET Salary = 25000.00 WHERE ID > 2;"]
drop_q = ["DROP TABLE Employee;","DROP DATABASE mysqltest1;","DROP user test1;"]

# Testing API Query
for i in create_q
  check_API_query(i)
end
for i in q
  check_API_query(i)
end
for i in drop_q
  check_API_query(i)
end

# Testing API Meta

for i in create_q
  check_API_querymeta(i)
end
for i in q
  check_API_querymeta(i)
end
for i in drop_q
  check_API_querymeta(i)
end

listdsns()
listdrivers()
ODBC.disconnect(con)
println("\n\n\n******  SUMMARY ******\n")
println("Number of passed queries  = $Query_passed")
println("Number of failed queries  = $(Query_failed+Query_Error)")
println("Queries that generated errors = $Query_Error")
println("\n******  END OF SUMMARY ******\n\n\n")
