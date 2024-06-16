module ODBC

using Printf, Dates, UUIDs, Unicode, Random
using DecFP, DBInterface, Tables
export DBInterface

include("API.jl")
include("utils.jl")
include("dbinterface.jl")
include("load.jl")
include("catalog.jl")

"""
    ODBC.setdebug(debug::Bool=true, tracefile::String=joinpath(tempdir(), "odbc.log"))

Turn on ODBC library call tracing. This prints debug information to `tracefile` upon every
entry and exit from calls to the underlying ODBC library (unixODBC, iODBC, or odbc32).
Debugging can be turned off by passing `false`.

Note that setting tracing on/off requires resetting the ODBC environment, which means
any open statements/connections will be closed/invalid.

Also note that due to the persistent nature of ODBC config, setting tracing will
persist across Julia sessions, i.e. if you turn tracing on, then quit julia and start again
tracing will still be on, and will stay on until explicitly turned off.

The iODBC driver manager supports passing `stderr` as the `tracefile`, which will
print all tracing information into the julia session/repl.
"""
function setdebug(debug::Bool=true, tracefile::String=joinpath(tempdir(), "odbc.log"))
    if debug
        API.setdebug(true, tracefile)
        @info "Enabled tracing of odbc library calls to $tracefile"
    else
        API.setdebug(false, tracefile)
        @info "Disabled tracing of odbc library calls"
    end
    return
end

"""
    ODBC.setunixODBC(; kw...)

Set the ODBC driver manager used to unixODBC. By default, ODBC.jl sets the `ODBCINI` and
`ODBCSYSINI` environment variables to the ODBC.jl-managed "scratch" location, but users may override
these (or provide additional environment variables) via `kw...` keyword arguments
this this function. The env variables will be set before allocating the ODBC environemnt.

Note that the odbc driver shared libraries can be "sticky" with regards to changing to
system configuration files. You may need to set a `OVERRIDE_ODBCJL_CONFIG` environment
variable before starting `julia` and running `import ODBC` to ensure that no environment
variables are changed by ODBC.jl itself.

While a unixODBC driver manager shared library is available for every platform, do note
that individual ODBC driver libraries may not be compatible with unixODBC on your system;
for example, if a driver library is built against iODBC, but unixODBC is the driver manager.
"""
setunixODBC(; kw...) = API.setunixODBC(; kw...)

"""
    ODBC.setiODBC(; kw...)

Set the ODBC driver manager used to iODBC. By default, ODBC.jl sets the `ODBCINI` and
`ODBCINSTINI` environment variables to the ODBC.jl-managed "scratch" location, but users may override
these (or provide additional environment variables) via `kw...` keyword arguments
this this function. The env variables will be set before allocating the ODBC environemnt.

Note that the odbc driver shared libraries can be "sticky" with regards to changing to
system configuration files. You may need to set a `OVERRIDE_ODBCJL_CONFIG` environment
variable before starting `julia` and running `import ODBC` to ensure that no environment
variables are changed by ODBC.jl itself.

While the iODBC driver manager shared library is available for non-windows platforms, do note
that individual ODBC driver libraries may not be compatible with unixODBC on your system;
for example, if a driver library is built against unixODBC, but iODBC is the driver manager.
"""
setiODBC(; kw...) = API.setiODBC(; kw...)

"""
    ODBC.setodbc32(; kw...)

Set the ODBC driver manager used to odbc32. On windows, ODBC.jl uses the system-wide
configurations for drivers and datasources. Drivers and datasources can still be added
via `ODBC.adddriver`/`ODBC.removedriver` and `ODBC.adddsn`/`ODBC.removedsn`, but you must
have administrator privileges in the Julia session. This is accomplished easiest by pressing
CTRL then right-clicking on the terminal/Julia application and choosing "Run as administrator".
"""
setodbc32(; kw...) = API.setodbc32(; kw...)

# driver/dsn management
"""
    ODBC.drivers() -> Dict

List installed ODBC drivers. The primary config location for installed drivers on non-windows platforms is
a reserved "scratch" space directory, i.e. an ODBC.jl-managed
location. Other system/user locations may also be checked (and are used by default on windows)
by the underlying ODBC driver manager, but for the most consistent results, aim to allow ODBC.jl to manage
installed drivers/datasources via `ODBC.addriver`, `ODBC.removedriver`, etc.

Note that the odbc driver shared libraries can be "sticky" with regards to changing to
system configuration files. You may need to set a `OVERRIDE_ODBCJL_CONFIG` environment
variable before starting `julia` and running `import ODBC` to ensure that no environment
variables are changed by ODBC.jl itself.

On windows, ODBC.jl uses the system-wide configurations for drivers and datasources. Drivers and
datasources can still be added via `ODBC.adddriver`/`ODBC.removedriver` and `ODBC.adddsn`/`ODBC.removedsn`,
but you must have administrator privileges in the Julia session. This is accomplished easiest by pressing
CTRL then right-clicking on the terminal/Julia application and choosing "Run as administrator".
"""
drivers() = API.getdrivers()

"""
    ODBC.dsns() -> Dict

List installed ODBC datasources. The primary config location for installed datasources on non-windows platforms is
a reserved "scratch" space directory, i.e. an ODBC.jl-managed
location. Other system/user locations may also be checked (and are by default on windows) by the underlying ODBC
driver manager, but for the most consistent results, aim to allow ODBC.jl to manage
installed drivers/datasources via `ODBC.adddsn`, `ODBC.removedsn`, etc.

Note that the odbc driver shared libraries can be "sticky" with regards to changing to
system configuration files. You may need to set a `OVERRIDE_ODBCJL_CONFIG` environment
variable before starting `julia` and running `import ODBC` to ensure that no environment
variables are changed by ODBC.jl itself.

On windows, ODBC.jl uses the system-wide configurations for drivers and datasources. Drivers and
datasources can still be added via `ODBC.adddriver`/`ODBC.removdriver` and `ODBC.adddsn`/`ODBC.removedsn`,
but you must have administrator privileges in the Julia session. This is accomplished easiest by pressing
CTRL then right-clicking on the terminal/Julia application and choosing "Run as administrator".
"""
dsns() = API.getdsns()

"""
    ODBC.adddriver(name, libpath; kw...)

Install a new ODBC driver. `name` is a user-provided "friendly" name to identify
the driver. `libpath` is the absolute path to the ODBC driver shared library.
Other key-value driver properties can be provided by the `kw...` keyword arguments.

This method is provided to try and provide the simplest/easiest/most consistent setup
experience for installing a new driver. Editing configuration files by hand is error-prone
and it's easy to miss adding something that is required.

While ODBC.jl supports all 3 major ODBC driver managers (unixODBC, iODBC, and odbc32),
be aware that most DBMS ODBC driver libraries are built against only one of the 3 and
can lead to compatibility issues if a different driver manager is used. This is mainly
an issue for driver libraries built against iODBC and then tried to use with unixODBC
or vice-versa.

On windows, ODBC.jl uses the system-wide configurations for drivers and datasources. Drivers and
datasources can still be added via `ODBC.adddriver`/`ODBC.removdriver` and `ODBC.adddsn`/`ODBC.removedsn`,
but you must have administrator privileges in the Julia session. This is accomplished easiest by pressing
CTRL then right-clicking on the terminal/Julia application and choosing "Run as administrator".
"""
adddriver(name, libpath; kw...) = API.adddriver(name, libpath; kw...)

"""
    ODBC.removedriver(name; removedsns::Bool=true)

Remove an installed ODBC driver by `name` (as returned from `ODBC.drivers()`).
`removedsns=true` also removes any datasources that were specified to use the driver.

On windows, ODBC.jl uses the system-wide configurations for drivers and datasources. Drivers and
datasources can still be added via `ODBC.adddriver`/`ODBC.removdriver` and `ODBC.adddsn`/`ODBC.removedsn`,
but you must have administrator privileges in the Julia session. This is accomplished easiest by pressing
CTRL then right-clicking on the terminal/Julia application and choosing "Run as administrator".
"""
removedriver(name; removedsns::Bool=true) = API.removedriver(name, removedsns)

"""
    ODBC.adddsn(name, driver; kw...)

Install a new ODBC datasource. `name` is a user-provided "friendly" name to identify
the datasource (dsn). `driver` is the "friendly" driver name that should be used to
connect to the datasource (valid driver options can be seen from `ODBC.drivers()`).
Additional connection key-value properties can be provided by the `kw...` keyword arguments.

Datasources can be connected by calling `DBInterface.connect(ODBC.Connection, dsn, user, pwd)`,
where `dsn` is the friendly datasource name, `user` is the username, and `pwd` is the password.

An alternative approach to installing datasources is to generate a valid "connection string"
that includes all connection properties in a single string passed to `DBInterface.connect`.
[www.connectionstrings.com](https://www.connectionstrings.com/) is a convenient resource
that provides connection string templates for various database systems.

On windows, ODBC.jl uses the system-wide configurations for drivers and datasources. Drivers and
datasources can still be added via `ODBC.adddriver`/`ODBC.removdriver` and `ODBC.adddsn`/`ODBC.removedsn`,
but you must have administrator privileges in the Julia session. This is accomplished easiest by pressing
CTRL then right-clicking on the terminal/Julia application and choosing "Run as administrator".
"""
adddsn(name, driver; kw...) = API.adddsn(name, driver; kw...)

"""
    ODBC.removedsn(name)

Remove an installed datasource by `name` (as returned from `ODBC.dsns()`).

On windows, ODBC.jl uses the system-wide configurations for drivers and datasources. Drivers and
datasources can still be added via `ODBC.adddriver`/`ODBC.removdriver` and `ODBC.adddsn`/`ODBC.removedsn`,
but you must have administrator privileges in the Julia session. This is accomplished easiest by pressing
CTRL then right-clicking on the terminal/Julia application and choosing "Run as administrator".
"""
removedsn(name) = API.removedsn(name)

end #ODBC module
