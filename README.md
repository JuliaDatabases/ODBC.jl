ODBC.jl
=======

A low-level ODBC interface for the Julia programming language


Current Version: Developer Preview v0.0.0


The ODBC Julia module header file is ODBC.jl. The module contains SQL const definitions and 
function definitions aligned with the ODBC API (http://goo.gl/l0Zin) in the 'consts.jl' and 
'backend.jl' files, respectively.

The package is officially listed in the Julia package manager now, so users can load the ODBC package as follows:
<br><br>(The first two commands below load and initialize the package manager)
> require("pkg.jl")     #Loads the package manager code <br>
> Pkg.init()    #Creates the package repository (if not already done)<br>
> Pkg.add("ODBC")    #Creates the repo and downloads the ODBC package <br>
> using ODBC    #Tells Julia to load and look in the ODBC module when you use ODBC-defined functions <br>

Defined functions can be split into two categories: user-facing and backend. The user-facing functions defined
so far are:

* Connect() 
* AdvancedConnect()
* Query()
* ListDrivers()
* ListDatasources()
* Disconnect()

These functions implement the backend functions which are built to mirror the
ODBC defined functions very closely (along with appropriate error-handling). 

Connect(DSN, username, password): Connect requires the DSN string argument as the name of a pre-defined ODBC datasource.
Valid datasources (DSNs) must first be setup through the ODBC administrator prior to connecting in Julia. The 'username' and
'password' arguments are optional as they may already be defined in the datasource. Connect() returns a Connection 
object which contains basic information about the connection and ODBC connection and statement handles. Typically,
Connect() is implemented by storing the Connection object in a variable to be able to disconnect or facilitate
handling multiple connections. It's unneccesary to store the object though, as a global 'conn' object holds the most
recently created Connection object and other ODBC functions will use it by default in the absence of a specified
connection.

AdvancedConnect(connectionstring): AdvancedConnect implements the native ODBC SQLDriverConnect function which allows
flexibility in connecting to a datasource through specifying a 'connection string' (e.g. "DSN=userdsn;UID=johnjacob;PWD=jingle;")
See ODBC API documentation (http://goo.gl/uXTuk) for additional details. If the connection string doesn't contain enough
information for the driver to connect, the user will be prompted with the additional information needed. Furthermore,
if an empty string is provided ("") the ODBC administrator will be brought up where the user can select the DSN to which
to connect, even allowing the user to create a datasource or add a driver.

Query(connection, query): If a connection object isn't specified, the query will be executed against the default
connection (stored in the variable 'conn' if you'd like to inspect). Once the query is executed, the resultset is 
stored in a DataFrame. Results are pointed to in the connection object (connection.results).

ListDrivers() and Listdatasources(): These two functions take no arguments and invoke the driver manager to list 
installed drivers or defined user and system DSNs, respectively. 

Disconnect(connection object): Disconnect closes the open connection object, frees all handles and resets the default
connection object as necessary. If invoked with no arguments (i.e. 'Disconnect()'), the default connection is closed.

Issues:
* I've had trouble being able to test on Linux and OSX systems, so the ODBC driver manager shared object libraries 
may not work correctly. If someone could help in testing, I'd really appreciate it
* I have a list of potential features to implement listed in a TODO file in this repository, suggestions welcome.
* Please send feedback! I feel like this has gotten to a point where I can share, but it's definitely far from where
I'd like to be

-Jacob
quinn.jacobd@gmail.com
