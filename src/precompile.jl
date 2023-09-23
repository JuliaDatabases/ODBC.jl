# Precompilation directives for ODBC.jl.

function _precompile()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing

    precompile(DBInterface.execute, (Connection, String))
end

_precompile()
