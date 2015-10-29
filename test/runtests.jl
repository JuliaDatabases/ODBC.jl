#Edit these credentials accordingly

DSN = "Default"
Username = "root"
Password = "password"


using DataFrames
using ODBC
con = ODBC.connect(DSN)
global Query_passed = 0
global Query_failed = 0
global Query_Error = 0
global query_counter = 0
global querymeta_counter = 0

function check_API_query(q,print_file=0,negative_testing=false)
  global Query_passed
  global Query_failed
  global Query_Error
  global query_counter
  global querymeta_counter
  try
    if print_file == 1
      query_counter  = query_counter  +1
      ODBC.query(q,output="query$query_counter.csv",delim=':')
    else
      a = ODBC.query(q)
      if (typeof(a) == DataFrame)
        Query_passed = Query_passed + 1
        #println("API query <$q> passed")
      else
        println("\n\nAPI query <$q> failed\n\n")
        Query_failed = Query_failed + 1
      end
    end
    if(negative_testing)
      println("\n\nAPI query <$q> failed the negative test\n\n")
      Query_failed = Query_failed + 1
    end
  catch
    if(!negative_testing)
      println("\n\n\nQuery \n<$q>\n is generating an error, please revise your query\n\n\n")
      Query_Error = Query_Error + 1
      return
    end
    #println("API query <$q> passed")
    Query_passed = Query_passed + 1
  end
end

function check_API_querymeta(q,print_file=0,negative_testing=false)
  global Query_passed
  global Query_failed
  global Query_Error
  global query_counter
  global querymeta_counter
  try
    if print_file == 1
      querymeta_counter = querymeta_counter +1
      ODBC.query(q,output="querymeta$querymeta_counter.csv",delim=':')
    else
      a = ODBC.querymeta(q)
      if (typeof(a) == Metadata)
        #println("API querymeta <$q> passed")
        Query_passed = Query_passed + 1
      else
        println("\n\nAPI querymeta <$q> failed\n\n")
        Query_failed = Query_failed + 1
      end
    end
    if(negative_testing)
      println("\n\nAPI query <$q> failed the negative test\n\n")
      Query_failed = Query_failed + 1
    end
  catch
    if(!negative_testing)
      println("\n\n\nQuery \n<$q>\n is generating an error, please revise your query\n\n\n")
      Query_Error = Query_Error + 1
      return
    end
    #println("API querymeta <$q> passed")
    Query_passed = Query_passed + 1
  end
end

q = ["show databases;", "use mysqltest1;", "show tables;", "select * from Employee;", "select count(*) from Employee;", "show columns from Employee;", "select ID from Employee group by ID;", "select * from Employee where Salary = -1;","select count(*) from Employee where OfficeNo > 0;", "select * from Employee where OfficeNo > 2 limit 2;","select a.ID, b.ID from Employee a left outer join Employee b on a.ID = b.ID where a.OfficeNo > 2 and b.OfficeNo < 45;","select * from Employee where JobType=\'HR\' and LunchTime=\'12:0:0\';","select * from Employee where Salary is null;"]
create_q = ["CREATE DATABASE mysqltest1;","CREATE USER test1 IDENTIFIED BY 'test1';","GRANT ALL ON mysqltest1.* TO test1;","use mysqltest1","CREATE TABLE Employee(ID INT NOT NULL AUTO_INCREMENT,Name VARCHAR(255),Salary FLOAT,JoinDate DATE,LastLogin DATETIME,LunchTime TIME,OfficeNo TINYINT,JobType ENUM('HR', 'Management', 'Accounts'),Senior BIT(18),empno SMALLINT,PRIMARY KEY (ID));","SET autocommit = 0;","START TRANSACTION WITH CONSISTENT SNAPSHOT;","INSERT INTO Employee (Name, Salary, JoinDate, LastLogin, LunchTime, OfficeNo, JobType, Senior, empno) VALUES ('John', 10000.50, '2015-8-3', '2015-9-5 12:31:30', '12:00:00', 1, 'HR', b'1', 1301), ('Tom', 20000.25, '2015-8-4', '2015-10-12 13:12:14', '13:00:00', 12, 'HR', b'1', 1422), ('Jim', 30000.00, '2015-6-2', '2015-9-5 10:05:10', '12:30:00', 45, 'Management', b'0', 1567), ('Tim', 15000.50, '2015-7-25', '2015-10-10 12:12:25', '12:30:00', 56, 'Accounts', b'1', 3200);","UPDATE Employee SET Salary = 25000.00 WHERE ID > 2;","INSERT INTO Employee VALUES ();","delete from Employee where name is null;"]
drop_q = ["DROP TABLE Employee;","DROP DATABASE mysqltest1;","DROP user test1;"]


# Testing API Query
for i in create_q
  check_API_query(i)
end
check_API_query("commit;")
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
check_API_querymeta("rollback;")
for i in q
  check_API_querymeta(i)
end
for i in drop_q
  check_API_querymeta(i)
end


#=  COMMENTED BECAUSE WRITING OUTPUT ONTO A FILE IS NOT WORKING, THIS IS A KNOWN ISSUE
#Writing output onto a file
# Testing API Query
for i in create_q
  check_API_query(i,1)
end
for i in q
  check_API_query(i,1)
end
for i in drop_q
  check_API_query(i,1)
end
# Testing API Meta
for i in create_q
  check_API_querymeta(i,1)
end
for i in q
  check_API_querymeta(i,1)
end
for i in drop_q
  check_API_querymeta(i,1)
end
=#

#Testing Macros
if typeof(@sql_str("show databases;")) == DataFrame
  Query_passed = Query_passed + 1
  #println("Macro @sql_str passed the test")
else
  Query_failed = Query_failed + 1
  println("\n\nMacro @sql_str passed failed the test\n\n")
end
if typeof(@query("show databases;")) == DataFrame
  Query_passed = Query_passed + 1
  #println("Macro @query passed the test")
else
  Query_failed = Query_failed + 1
  println("\n\nMacro @query failed the test\n\n")
end


listdsns()
listdrivers()
ODBC.disconnect(con)

#Testing advanced connect
try
  con1 = ODBC.advancedconnect("DSN=$DSN;UID=$Username;PWD=$Password;")
  #println("Connected successfully using Advanced Connect")
  Query_passed = Query_passed + 1
  ODBC.disconnect(con1)
catch
  Query_Error = Query_Error + 1
  println("\n\nError in connecting through advanced connect\n\n")
end



                                          #NEGATIVE TESTING


println("\n\n\t\t\t******  NEGATIVE TESTING ******\n\n")
error_q = ["select count(*) from Employee; select count(*) from Employee;","select * from Employee where Coloumn_Not_Present > 2 limit 2;","select * from Table_not_present where Office > 2 limit 2;","use Inexistent_DataBase;", "CREATE DATABASE mysqltest1;", "CREATE DATABASE mysqltest1;", "CREATE USER test1 IDENTIFIED BY 'test1';", "CREATE USER test1 IDENTIFIED BY 'test1';", "GRANT ALL ON Inexistent_DataBase.* TO test1;", "DROP user test1;", "GRANT ALL ON mysqltest1.* TO test1;", "use mysqltest1","use mysqltest1", "CREATE TABLE Employee(ID INT NOT NULL AUTO_INCREMENT,Name VARCHAR(255),Salary FLOAT,JoinDate DATE,LastLogin DATETIME,LunchTime TIME,OfficeNo TINYINT,JobType ENUM('HR', 'Management', 'Accounts'),Senior BIT(18),empno SMALLINT,PRIMARY KEY (ID));","CREATE TABLE Employee(ID INT NOT NULL AUTO_INCREMENT,Name VARCHAR(255))","CREATE TABLE ERROR(ID I,Name VARCHAR)","INSERT INTO Employee (Name, Salary, JoinDate, LastLogin, LunchTime, OfficeNo, JobType, Senior, empno) VALUES ('John', , '2015-8-3', '2015-9-5 12:31:30', '12:00:00', 1, 'HR', b'1', 1301)","DROP TABLE inexistent;","DROP TABLE Employee;","DROP TABLE Employee;","DROP DATABASE mysqltest1;","DROP DATABASE mysqltest1;"]
con = ODBC.connect(DSN)

# Testing API Query
for i in error_q
  check_API_query(i,0,true)
end

# Testing API Meta
for i in error_q
  check_API_querymeta(i,0,true)
end
ODBC.disconnect(con)

#Testing AdvancedConnect and connect with incorrect credentials
try
  con2 = ODBC.connect("Incorrect")
  Query_failed = Query_failed + 1
  println("Test failed while testing function Connect because ODBC connected inspite of incorrect DSN")
catch
  Query_passed = Query_passed + 1
end
try
  con3 = ODBC.advancedconnect("DSN=$DSN;UID=$Username;PWD=pasword;")
  Query_failed = Query_failed + 1
  println("Test failed while testing Advanced Connect function because ODBC connected inspite of incorrect Password")
catch
  Query_passed = Query_passed + 1
end
try
  con3 = ODBC.advancedconnect("DSN=$DSN;UID=rot;PWD=$Password;")
  Query_failed = Query_failed + 1
  println("Test failed while testing Advanced Connect function because ODBC connected inspite of incorrect Username")
catch
  Query_passed = Query_passed + 1
end
try
  con3 = ODBC.advancedconnect("DSN=$DSN;UID=rot;PWD=$Password;",driver_prompt=435)
  Query_failed = Query_failed + 1
  println("Test failed while testing Advanced Connect function because ODBC connected inspite of incorrect Username and incorrect argument")
catch
  Query_passed = Query_passed + 1
end


println("\n\n\n******  SUMMARY ******\n")
println("Number of passed queries  = $Query_passed")
println("Number of failed queries  = $Query_failed")
println("Queries that generated errors = $Query_Error")
println("Total number of queries executed: $(Query_failed+Query_Error+Query_passed)")
println("\n******  END OF SUMMARY ******\n\n\n")
