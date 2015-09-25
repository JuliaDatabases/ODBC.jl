using DataFrames
using ODBC
con = ODBC.connect("Default")
function check_API_query(q)
  try
    a = ODBC.query(q)
    if (typeof(a) == DataFrame)
      println("API query <$q> passed")
    else
      println("API query <$q> failed")
    end
  catch
    println("\nQuery \n<$q>\n is generating an error, please revise your query\n")
    return
  end
end
function check_API_querymeta(q)

  try
    a = ODBC.querymeta(q)
    if (typeof(a) == Metadata)
      println("API querymeta <$q> passed")
    else
      println("API querymeta <$q> failed")
    end
  catch
    println("\nQuery \n<$q>\n is generating an error, please revise your query\n")
    return
  end
end
# Multi Statement is not supported by this wrapper, a multi-statement has been intentionally added
q = ["show databases;", "use dbtest;", "show tables;", "select * from employee;", "select count(*) from employee;", "show columns from employee;", "select id from employee group by id;", "select * from employee where mid = -1;","select count(*) from employee where mid = 0;", "select * from employee where mid = 2 limit 20;","select count(*) from employee; select count(*) from employee;","select a.id, b.id from employee a left outer join employee b on a.id = b.id where a.mid = 2 and b.mid = 0;"]
create_q = ["CREATE DATABASE mysqltest1;","CREATE USER test1 IDENTIFIED BY 'test1';","GRANT ALL ON mysqltest1.* TO test1;","use mysqltest1","CREATE TABLE Employee(ID INT NOT NULL AUTO_INCREMENT,Name VARCHAR(255),Salary FLOAT,JoinDate DATE,LastLogin DATETIME,LunchTime TIME,OfficeNo TINYINT,JobType ENUM('HR', 'Management', 'Accounts'),Senior BIT(1),empno SMALLINT,PRIMARY KEY (ID));","INSERT INTO Employee (Name, Salary, JoinDate, LastLogin, LunchTime, OfficeNo, JobType, Senior, empno) VALUES ('John', 10000.50, '2015-8-3', '2015-9-5 12:31:30', '12:00:00', 1, 'HR', b'1', 1301), ('Tom', 20000.25, '2015-8-4', '2015-10-12 13:12:14', '13:00:00', 12, 'HR', b'1', 1422), ('Jim', 30000.00, '2015-6-2', '2015-9-5 10:05:10', '12:30:00', 45, 'Management', b'0', 1567), ('Tim', 15000.50, '2015-7-25', '2015-10-10 12:12:25', '12:30:00', 56, 'Accounts', b'1', 3200);","UPDATE Employee SET Salary = 25000.00 WHERE ID > 2;"]
drop_q = ["DROP TABLE Employee;","DROP DATABASE mysqltest1;","DROP user test1;"]
for i in q
  check_API_query(i)
  check_API_querymeta(i)
end
for i in create_q
  check_API_query(i)
end
for i in drop_q
  check_API_query(i)
end
for i in create_q
  check_API_querymeta(i)
end
for i in drop_q
  check_API_querymeta(i)
end

listdsns()
listdrivers()
ODBC.disconnect(con)
