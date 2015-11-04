#Edit these credentials accordingly

DSN = "Default"
Username = "root"
Password = "root"


using DataFrames,ODBC
using JLD, HDF5
con = ODBC.connect(DSN)
global Query_passed = 0
global Query_failed = 0
global Query_Error = 0
global query_counter = 0
global querymeta_counter = 0

function check_correctness(q,a)
  if q == "CREATE DATABASE mysqltest1;"
    cross_check = ODBC.query("show databases;")
    try
      if "mysqltest1" in cross_check[:Database]
        return true
      end
    catch
      return false
    end
  end
  if q == "CREATE USER test1 IDENTIFIED BY 'test1';"
    cross_check = ODBC.query("SELECT User FROM mysql.user;")
    try
      if "test1" in cross_check[:User]
        return true
      end
    catch
      return false
    end
  end
  if q == "GRANT ALL ON mysqltest1.* TO test1;"
    cross_check = ODBC.query("show grants for 'test1';")
    try
      if "GRANT ALL PRIVILEGES ON `mysqltest1`.* TO 'test1'@'%'" in cross_check[:Grants_for_test1_]
        return true
      end
    catch
      return false
    end
  end

  if q == "CREATE TABLE Employee(ID INT NOT NULL AUTO_INCREMENT,Name VARCHAR(255),Salary FLOAT,JoinDate DATE,LastLogin DATETIME,LunchTime TIME,OfficeNo TINYINT,JobType ENUM('HR', 'Management', 'Accounts'),Senior BIT(18),empno SMALLINT,PRIMARY KEY (ID));"
    cross_check = ODBC.query("desc Employee;")
    correct_answer = load("./dataset/desc.jld")["desc"]
    try
      if isequal(cross_check,correct_answer)
        return true
      end
    catch
      return false
    end
  end

  if q == "SET autocommit = 0;"
    cross_check = ODBC.query("select @@autocommit;")
    try
      if cross_check[:_autocommit][1] == 0
        return true
      end
    catch
      return false
    end
  end

  if q == "START TRANSACTION WITH CONSISTENT SNAPSHOT;"
    cross_check = ODBC.query("select @@autocommit;")
    try
      if cross_check[:_autocommit][1] == 1
        return true
      end
    catch
      return false
    end
  end

  if q == "INSERT INTO Employee (Name, Salary, JoinDate, LastLogin, LunchTime, OfficeNo, JobType, Senior, empno) VALUES ('John', 10000.50, '2015-8-3', '2015-9-5 12:31:30', '12:00:00', 1, 'HR', b'1', 1301), ('Tom', 20000.25, '2015-8-4', '2015-10-12 13:12:14', '13:00:00', 12, 'HR', b'1', 1422), ('Jim', 30000.00, '2015-6-2', '2015-9-5 10:05:10', '12:30:00', 45, 'Management', b'0', 1567), ('Tim', 15000.50, '2015-7-25', '2015-10-10 12:12:25', '12:30:00', 56, 'Accounts', b'1', 3200);"
    cross_check = ODBC.query("select * from Employee")
    correct_answer = load("./dataset/select_all.jld")["select_all"]
    try
      if isequal(cross_check,correct_answer)
        return true
      end
    catch
      return false
    end
  end

  if q == "UPDATE Employee SET Salary = 25000.00 WHERE ID > 2;"
    cross_check = ODBC.query("select ID,Salary from Employee WHERE ID > 2;")
    correct_answer = load("./dataset/update.jld")["update"]
    try
      if isequal(cross_check,correct_answer)
        return true
      end
    catch
      return false
    end
  end

  if q == "INSERT INTO Employee VALUES ();"
    cross_check = ODBC.query("select ID,Salary from Employee WHERE Salary is null;")
    correct_answer = load("./dataset/insert_null.jld")["insert_null"]
    try
      if isequal(cross_check,correct_answer)
        return true
      end
    catch
      return false
    end
  end

  if q == "delete from Employee where name is null;"
    cross_check = ODBC.query("select ID,Salary from Employee WHERE Salary is null;")
    try
      if size(cross_check) == (0,0)
        return true
      end
    catch
      return false
    end
  end

  return true
end

function check_API_query(q,print_file=0,negative_testing=false)
  global Query_passed
  global Query_failed
  global Query_Error
  global query_counter
  global querymeta_counter
  try
    query_counter  = query_counter  +1
    if print_file == 1
      ODBC.query(q,output="query$query_counter.csv",delim=':')
    else
      a = ODBC.query(q)
      if (typeof(a) == DataFrame) && !(negative_testing) && check_correctness(q,a)
        Query_passed = Query_passed + 1
        #println("API query <$q> passed")
      else
        println("\n\nAPI query <$q> failed\n\n")
        Query_failed = Query_failed + 1
      end
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
    querymeta_counter = querymeta_counter +1
    if print_file == 1
      ODBC.query(q,output="querymeta$querymeta_counter.csv",delim=':')
    else
      a = ODBC.querymeta(q)
      if (typeof(a) == Metadata) && !(negative_testing)
        #println("API querymeta <$q> passed")
        Query_passed = Query_passed + 1
      else
        println("\n\nAPI querymeta <$q> failed\n\n")
        Query_failed = Query_failed + 1
      end
    end
  catch
    if(!negative_testing)
      println("\n\n\nQuery \n<$q>\n is generating an error, please revise your query in querymeta\n\n\n")
      Query_Error = Query_Error + 1
      return
    end
    #println("API querymeta <$q> passed")
    Query_passed = Query_passed + 1
  end
end

function ODBC_test()
  global Query_passed
  global Query_failed
  global Query_Error
  global query_counter
  global querymeta_counter
  #check_API_query("drop database mysqltest1",0,true)
  q = ["use mysqltest1;",  "select * from Employee;", "select count(*) from Employee;", "show columns from Employee;", "select ID from Employee group by ID;", "select * from Employee where Salary = -1;","select count(*) from Employee where OfficeNo > 0;", "select * from Employee where OfficeNo > 2 limit 2;","select a.ID, b.ID from Employee a left outer join Employee b on a.ID = b.ID where a.OfficeNo > 2 and b.OfficeNo < 45;","select * from Employee where JobType=\'HR\' and LunchTime=\'12:0:0\';","select * from Employee where Salary is null;"]
  create_q = ["CREATE DATABASE mysqltest1;","CREATE USER test1 IDENTIFIED BY 'test1';","GRANT ALL ON mysqltest1.* TO test1;","use mysqltest1","CREATE TABLE Employee(ID INT NOT NULL AUTO_INCREMENT,Name VARCHAR(255),Salary FLOAT,JoinDate DATE,LastLogin DATETIME,LunchTime TIME,OfficeNo TINYINT,JobType ENUM('HR', 'Management', 'Accounts'),Senior BIT(18),empno SMALLINT,PRIMARY KEY (ID));","SET autocommit = 0;","START TRANSACTION WITH CONSISTENT SNAPSHOT;","INSERT INTO Employee (Name, Salary, JoinDate, LastLogin, LunchTime, OfficeNo, JobType, Senior, empno) VALUES ('John', 10000.50, '2015-8-3', '2015-9-5 12:31:30', '12:00:00', 1, 'HR', b'1', 1301), ('Tom', 20000.25, '2015-8-4', '2015-10-12 13:12:14', '13:00:00', 12, 'HR', b'1', 1422), ('Jim', 30000.00, '2015-6-2', '2015-9-5 10:05:10', '12:30:00', 45, 'Management', b'0', 1567), ('Tim', 15000.50, '2015-7-25', '2015-10-10 12:12:25', '12:30:00', 56, 'Accounts', b'1', 3200);","UPDATE Employee SET Salary = 25000.00 WHERE ID > 2;","INSERT INTO Employee VALUES ();","delete from Employee where name is null;"]
  drop_q = ["DROP TABLE Employee;","DROP DATABASE mysqltest1;","DROP user test1;","FLUSH PRIVILEGES;"]

  cross_check_create_q = ["show databases;", "SELECT User FROM mysql.user;", "show grants for 'test1';", "show tables;","desc Employee;","select @@autocommit;","select @@autocommit;","select Salary for Employee where WHERE ID > 2;","select ID from Employee where Salary is null;","select ID from Employee where Salary is null;"]


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
  ODBC.disconnect()

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


  println("\n\n\t\t\t******  NEGATIVE TESTING ******\n\n");
  error_q = ["select count(*) from Employee; select count(*) from Employee;","select * from Employee where Coloumn_Not_Present > 2 limit 2;","select * from Table_not_present where Office > 2 limit 2;","use Inexistent_DataBase;", "CREATE DATABASE mysqltest1;", "CREATE DATABASE mysqltest1;", "CREATE USER test1 IDENTIFIED BY 'test1';", "CREATE USER test1 IDENTIFIED BY 'test1';", "DROP user test1;","FLUSH PRIVILEGES;", "use mysqltest1", "CREATE TABLE Employee(ID INT NOT NULL AUTO_INCREMENT,Name VARCHAR(255),Salary FLOAT,JoinDate DATE,LastLogin DATETIME,LunchTime TIME,OfficeNo TINYINT,JobType ENUM('HR', 'Management', 'Accounts'),Senior BIT(18),empno SMALLINT,PRIMARY KEY (ID));","CREATE TABLE Employee(ID INT NOT NULL AUTO_INCREMENT,Name VARCHAR(255))","CREATE TABLE ERROR(ID I,Name VARCHAR)","INSERT INTO Employee (Name, Salary, JoinDate, LastLogin, LunchTime, OfficeNo, JobType, Senior, empno) VALUES ('John','John' , 2015-99-99, 2015-99-5 , 92:00:00, 1.23, 'HRD', b'101001', 1301.56)","DROP TABLE inexistent;","DROP TABLE Employee;","DROP TABLE Employee;","DROP DATABASE mysqltest1;","DROP DATABASE mysqltest1;", "delete from Employee where Nam='Whatever';","UPDATE Employee SET Salary = 25000.00 WHERE ID > 1;","CREATE TABLE Employee(ID INT NOT NULL AUTO_INCREMENT,Name VARCHAR(255))","create database mysqltest1","use mysqltest1","CREATE TABLE Employee(ID INT NOT NULL AUTO_INCREMENT,Name VARCHAR(255),PRIMARY KEY (ID));","insert into Employee(Name) values('Whatever')","delete from Employee where Nam='Whatever';","UPDATE Employee SET Salary = 25000.00 WHERE ID > 1;","DROP TABLE Employee;","DROP DATABASE mysqltest1;"]
  skip_error_q = [5,7,9,10,11,12,17,19,24,25,26,27,30,31]
  con = ODBC.connect(DSN)
  error_q_counter=1
  # Testing API Query
  for i in error_q
    if error_q_counter in skip_error_q
      check_API_query(i,0)
    else
      check_API_query(i,0,true)
    end
    error_q_counter = error_q_counter+1
  end

  error_q_counter=1
  # Testing API Meta
  for i in error_q
    if error_q_counter in skip_error_q
      check_API_querymeta(i,0)
    else
      check_API_querymeta(i,0,true)
    end
    error_q_counter = error_q_counter+1
  end
  ODBC.disconnect(con)

  try
    ODBC.query("show databases",con)
    Query_failed = Query_failed + 1
    println("Test failed because ODBC connection object being used is no longer valid and yet ODBC didn't generate an error")
  catch
    Query_passed = Query_passed + 1
  end


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

  #Indicates that current build of ODBC.jl has errors in it
  if Query_Error>0 || Query_failed>0
    exit(1)
  end
end
ODBC_test()
