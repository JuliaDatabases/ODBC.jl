# whether a julia value needs wrapped in an array in order to call pointer(value)
# needswrapped(x::API.SQLSMALLINT) = x != API.SQL_C_CHAR && x != API.SQL_C_WCHAR && x != API.SQL_C_BINARY
needswrapped(x::Union{String, Vector{UInt8}}) = false
needswrapped(x::DecFP.DecimalFloatingPoint) = false
needswrapped(x) = true
const MISSING_BUF = [missing]

# convert a julia value to the "C type" storage the driver expects
ccast(x) = x
ccast(x::Date) = API.SQLDate(x)
ccast(x::DateTime) = API.SQLTimestamp(x)
ccast(x::Time) = API.SQLTime(x)
ccast(x::DecFP.DecimalFloatingPoint) = string(x)

_zero(T) = zero(T)
_zero(::Type{UUID}) = UUID(0)

function newarray(T, nullable, rows)
    if nullable == API.SQL_NO_NULLS
        return Vector{T}(undef, rows)
    else
        A = Vector{Union{Missing, T}}(undef, rows)
        fill!(A, _zero(T))
        return A
    end
end

@inline function specialize(f, @nospecialize(x))
    if x isa Vector{Missing}
        return f(x)
    elseif x isa String
        return f(x)
    elseif x isa Vector{UInt8}
        return f(x)
    elseif x isa Vector{Float32}
        return f(x)
    elseif x isa Vector{Float64}
        return f(x)
    elseif x isa Vector{Int8}
        return f(x)
    elseif x isa Vector{Int16}
        return f(x)
    elseif x isa Vector{Int32}
        return f(x)
    elseif x isa Vector{Int64}
        return f(x)
    elseif x isa Vector{Bool}
        return f(x)
    elseif x isa Vector{API.SQLDate}
        return f(x)
    elseif x isa Vector{API.SQLTimestamp}
        return f(x)
    elseif x isa Vector{API.SQLTime}
        return f(x)
    elseif x isa Vector{UUID}
        return f(x)
    elseif x isa Vector{Union{Missing, Float32}}
        return f(x)
    elseif x isa Vector{Union{Missing, Float64}}
        return f(x)
    elseif x isa Vector{Union{Missing, Int8}}
        return f(x)
    elseif x isa Vector{Union{Missing, Int16}}
        return f(x)
    elseif x isa Vector{Union{Missing, Int32}}
        return f(x)
    elseif x isa Vector{Union{Missing, Int64}}
        return f(x)
    elseif x isa Vector{Union{Missing, Bool}}
        return f(x)
    elseif x isa Vector{Union{Missing, API.SQLDate}}
        return f(x)
    elseif x isa Vector{Union{Missing, API.SQLTimestamp}}
        return f(x)
    elseif x isa Vector{Union{Missing, API.SQLTime}}
        return f(x)
    elseif x isa Vector{Union{Missing, UUID}}
        return f(x)
    end
end

mutable struct Buffer
    buffer::Union{
        Vector{Missing},
        String,
        Vector{UInt8},
        Vector{Float32},
        Vector{Float64},
        Vector{Int8},
        Vector{Int16},
        Vector{Int32},
        Vector{Int64},
        Vector{Bool},
        Vector{API.SQLDate},
        Vector{API.SQLTimestamp},
        Vector{API.SQLTime},
        Vector{UUID},
        Vector{Union{Missing, Float32}},
        Vector{Union{Missing, Float64}},
        Vector{Union{Missing, Int8}},
        Vector{Union{Missing, Int16}},
        Vector{Union{Missing, Int32}},
        Vector{Union{Missing, Int64}},
        Vector{Union{Missing, Bool}},
        Vector{Union{Missing, API.SQLDate}},
        Vector{Union{Missing, API.SQLTimestamp}},
        Vector{Union{Missing, API.SQLTime}},
        Vector{Union{Missing, UUID}},
    }

    # for parameter binding
    function Buffer(x)
        y = ccast(x)
        return new(needswrapped(x) ? Union{Missing, typeof(y)}[y] : y)
    end

    # for data fetching
    function Buffer(ctype::API.SQLSMALLINT, columnsize, rows, nullable)
        if ctype == API.SQL_C_DOUBLE
            return new(newarray(Float64, nullable, rows))
        elseif ctype == API.SQL_C_FLOAT
            return new(newarray(Float32, nullable, rows))
        elseif ctype == API.SQL_C_STINYINT
            return new(newarray(Int8, nullable, rows))
        elseif ctype == API.SQL_C_SSHORT
            return new(newarray(Int16, nullable, rows))
        elseif ctype == API.SQL_C_SLONG
            return new(newarray(Int32, nullable, rows))
        elseif ctype == API.SQL_C_SBIGINT
            return new(newarray(Int64, nullable, rows))
        elseif ctype == API.SQL_C_BIT
            return new(newarray(Bool, nullable, rows))
        elseif ctype == API.SQL_C_TYPE_DATE
            return new(newarray(API.SQLDate, nullable, rows))
        elseif ctype == API.SQL_C_TYPE_TIMESTAMP
            return new(newarray(API.SQLTimestamp, nullable, rows))
        elseif ctype == API.SQL_C_TYPE_TIME
            return new(newarray(API.SQLTime, nullable, rows))
        elseif ctype == API.SQL_C_GUID
            return new(newarray(UUID, nullable, rows))
        else
            return new(Vector{UInt8}(undef, columnsize * rows))
        end
    end

end

Base.pointer(b::Buffer) = specialize(pointer, b.buffer)
Base.pointer(b::Buffer, i) = specialize(x -> pointer(x, i), b.buffer)

function update!(b::Buffer, @nospecialize(x))
    if x === missing
        b.buffer = MISSING_BUF
    else
        y = ccast(x)
        if needswrapped(x)
            specialize(b.buffer) do buf
                if y isa eltype(buf)
                    buf[1] = y
                else
                    b.buffer = Union{Missing, typeof(y)}[y]
                end
            end
        else
            b.buffer = y
        end
    end
    return
end

# NOTE: this bufferlength only applies to parameter binding for strings/bytes
bufferlength(b::Buffer) = specialize(sizeof, b.buffer)

# https://docs.microsoft.com/en-us/sql/odbc/reference/appendixes/column-size?view=sql-server-ver15
columnsize(x) = 0
columnsize(x::Union{String, Vector{UInt8}}) = sizeof(x)
columnsize(x::Vector{T}) where {T <: Union{Float32, Float64}} = ndigits(trunc(Int, maxintfloat(T))) - 1
columnsize(x::Vector{Bool}) = 1
columnsize(x::Vector{T}) where {T <: Integer} = ndigits(typemax(T))
columnsize(x::Vector{API.SQLDate}) = 10
columnsize(x::Vector{API.SQLTime}) = 9
columnsize(x::Vector{API.SQLTimestamp}) = 20
columnsize(b::Buffer) = specialize(columnsize, b.buffer)

# https://docs.microsoft.com/en-us/sql/odbc/reference/appendixes/decimal-digits?view=sql-server-ver15
decimaldigits(x) = 0
decimaldigits(x::Vector{API.SQLTimestamp}) = length(rstrip(Printf.@sprintf("%.9f", 500000 / 1e9), '0')) - 2
decimaldigits(b::Buffer) = specialize(decimaldigits, b.buffer)

# returns (C type, SQL type) given an input julia value
# so: for a julia value, what should the C buffer be for binding the variable
# and what is the SQL type the driver should expect
bindtypes(x) = API.SQL_C_CHAR, API.SQL_VARCHAR
bindtypes(x::Int16) = API.SQL_C_SSHORT, API.SQL_SMALLINT
bindtypes(x::UInt16) = API.SQL_C_USHORT, API.SQL_SMALLINT
bindtypes(x::Int32) = API.SQL_C_SLONG, API.SQL_INTEGER
bindtypes(x::UInt32) = API.SQL_C_ULONG, API.SQL_INTEGER
bindtypes(x::Float32) = API.SQL_C_FLOAT, API.SQL_REAL
bindtypes(x::Float64) = API.SQL_C_DOUBLE, API.SQL_DOUBLE
bindtypes(x::Bool) = API.SQL_C_BIT, API.SQL_BIT
bindtypes(x::Int8) = API.SQL_C_STINYINT, API.SQL_TINYINT
bindtypes(x::UInt8) = API.SQL_C_UTINYINT, API.SQL_TINYINT
bindtypes(x::Int64) = API.SQL_C_SBIGINT, API.SQL_BIGINT
bindtypes(x::UInt64) = API.SQL_C_UBIGINT, API.SQL_BIGINT
bindtypes(x::Vector{UInt8}) = API.SQL_C_BINARY, API.SQL_VARBINARY
bindtypes(x::Date) = API.SQL_C_TYPE_DATE, API.SQL_TYPE_DATE
bindtypes(x::DateTime) = API.SQL_C_TYPE_TIMESTAMP, API.SQL_TYPE_TIMESTAMP
bindtypes(x::Time) = API.SQL_C_TYPE_TIME, API.SQL_TYPE_TIME
bindtypes(x::DecFP.DecimalFloatingPoint) = API.SQL_C_CHAR, API.SQL_DECIMAL
# bindtypes(x::DecFP.DecimalFloatingPoint) = API.SQL_C_NUMERIC
bindtypes(x::UUID) = API.SQL_C_GUID, API.SQL_GUID

const BINDTYPES = [
    Int8, Int16, Int32, Int64,
    UInt8, UInt16, UInt32, UInt64,
    Float32, Float64, DecFP.Dec64, DecFP.Dec128,
    Bool,
    Vector{UInt8}, String, UUID,
    Date, Time, DateTime
]

bindtypes(::Type{T}) where {T} = bindtypes(zero(T))
bindtypes(::Type{Vector{UInt8}}) = bindtypes(UInt8[])
bindtypes(::Type{String}) = bindtypes("")
bindtypes(::Type{T}) where {T <: Dates.TimeType} = bindtypes(T(0))
bindtypes(::Type{UUID}) = bindtypes(UUID(0))

# used for create table column type definitions
typeprecision(::Type{DecFP.Dec64}) = 16
typeprecision(::Type{DecFP.Dec128}) = 35
typeprecision(::Type{Float64}) = 15
typeprecision(::Type{Float32}) = 7
typeprecision(T) = 0
typescale(T) = 6

mutable struct Binding
    valuetype::API.SQLSMALLINT # C type for storage
    parametertype::API.SQLSMALLINT # SQL type for driver semantics
    value::Buffer
    bufferlength::API.SQLLEN
    strlen_or_indptr::Vector{Int}
    long::Bool
    totallen::Int
    
    # for binding julia values for execution
    function Binding(stmt, x, i)
        v, p = bindtypes(x)
        b = new()
        b.valuetype = v
        b.parametertype = p
        b.value = Buffer(x)
        b.strlen_or_indptr = [Int(x === missing ? API.SQL_NULL_DATA : bufferlength(b.value))]
        bindparam(stmt, i, b)
        return b
    end

    # for creating bindings for fetching data
    function Binding(stmt, columnar, i, ctype, sqltype, columnsize, nullable, long, rows)
        b = new()
        b.valuetype = ctype
        b.parametertype = sqltype
        b.value = Buffer(ctype, columnsize, rows, nullable)
        b.bufferlength = columnsize
        b.strlen_or_indptr = Vector{Int}(undef, rows)
        if columnar
            bindcol(stmt, i, b)
        end
        b.long = long
        b.totallen = 0
        return b
    end
end

function update!(stmt, b::Binding, @nospecialize(x), i)
    update!(b.value, x)
    v, p = bindtypes(x)
    b.valuetype = v
    b.parametertype = p
    b.bufferlength = bufferlength(b.value)
    b.strlen_or_indptr[1] = Int(x === missing ? API.SQL_NULL_DATA : bufferlength(b.value))
    bindparam(stmt, i, b)
    return
end

# unpack Binding/Buffer to call SQLBindParameter
bindparam(stmt, i, b::Binding) = API.bindparam(stmt, i, API.SQL_PARAM_INPUT,
    b.valuetype, b.parametertype, columnsize(b.value), decimaldigits(b.value), pointer(b.value), b.bufferlength, pointer(b.strlen_or_indptr))

# if no bindings have been made yet, allocate them fresh
bindparams(stmt, params, ::Nothing) = [Binding(stmt, x, i) for (i, x) in enumerate(params)]

# Bindings are being re-used, update w/ new values
function bindparams(stmt, params, bindings)
    for (i, x) in enumerate(params)
        update!(stmt, bindings[i], x, i)
    end
    return bindings
end

# using Binding/Buffer for data fetching
getbindings(stmt, columnar, ctypes, sqltypes, columnsizes, nullables, longtexts, rows) =
    [Binding(stmt, columnar, i, ctypes[i], sqltypes[i], columnsizes[i], nullables[i], longtexts[i], rows) for i = 1:length(ctypes)]

function getdata(stmt, i, b::Binding)
    status = API.SQLGetData(API.getptr(stmt), i, b.valuetype, pointer(b.value), b.bufferlength, b.strlen_or_indptr)
    b.totallen = b.strlen_or_indptr[1]
    if b.long && b.strlen_or_indptr[1] != API.SQL_NULL_DATA
        chardata = b.valuetype != API.SQL_C_BINARY
        if b.strlen_or_indptr[1] == API.SQL_NO_TOTAL
            b.totallen = b.bufferlength - 1
            while true
                # additional data to receive
                len = b.bufferlength
                b.bufferlength <<= 1
                resize!(b.value.buffer, b.bufferlength)
                newlen = b.bufferlength - len + chardata
                status = API.SQLGetData(API.getptr(stmt), i, b.valuetype, pointer(b.value, len + !chardata), newlen, b.strlen_or_indptr)
                ind = b.strlen_or_indptr[1]
                fetched = (ind >= newlen || ind == API.SQL_NO_TOTAL) ? newlen - chardata : ind
                tl = b.totallen
                b.totallen += fetched
                (status == API.SQL_NO_DATA || (ind != API.SQL_NO_TOTAL && ind < newlen)) && break
            end
        elseif b.strlen_or_indptr[1] >= b.bufferlength
            ind = b.strlen_or_indptr[1]
            len = b.bufferlength
            b.bufferlength += ind - b.bufferlength + chardata
            resize!(b.value.buffer, b.bufferlength)
            status = API.SQLGetData(API.getptr(stmt), i, b.valuetype, pointer(b.value, len + !chardata), b.bufferlength - len + chardata, b.strlen_or_indptr)
            b.totallen = b.bufferlength - chardata
        end
    end
    return
end

bindcol(stmt, i, b::Binding) = API.SQLBindCol(API.getptr(stmt), i, 
    b.valuetype, pointer(b.value), b.bufferlength, b.strlen_or_indptr)

function jlcast(::Type{T}, bytes) where {T <: DecFP.DecimalFloatingPoint}
    x = String(bytes)
    parse(T, x)
end
jlcast(::Type{Vector{UInt8}}, bytes) = bytes
jlcast(::Type{String}, bytes) = String(bytes)

# given the SQL type as described by the driver library
# what is the C storage needed for data transfer, and
# final Julia type (that may involve conversions from C layout)
function fetchtypes(x, prec)
    if x == API.SQL_DECIMAL
        if prec > 16
            return (API.SQL_C_CHAR, DecFP.Dec128)
        else
            # return (API.SQL_C_NUMERIC, DecFP.Dec64)
            return (API.SQL_C_CHAR, DecFP.Dec64)
        end
    elseif x == API.SQL_NUMERIC
        if prec > 16
            return (API.SQL_C_CHAR, DecFP.Dec128)
        else
            return (API.SQL_C_CHAR, DecFP.Dec64)
        end
    elseif x == API.SQL_SMALLINT
        return (API.SQL_C_SSHORT, Int16)
    elseif x == API.SQL_INTEGER
        return (API.SQL_C_SLONG, Int32)
    elseif x == API.SQL_REAL
        return (API.SQL_C_FLOAT, Float32)
    elseif x == API.SQL_FLOAT || x == API.SQL_DOUBLE
        return (API.SQL_C_DOUBLE, Float64)
    elseif x == API.SQL_BIT
        return (API.SQL_C_BIT, Bool)
    elseif x == API.SQL_TINYINT
        return (API.SQL_C_STINYINT, Int8)
    elseif x == API.SQL_BIGINT
        return (API.SQL_C_SBIGINT, Int64)
    elseif x == API.SQL_BINARY || x == API.SQL_VARBINARY || x == API.SQL_LONGVARBINARY
        return (API.SQL_C_BINARY, Vector{UInt8})
    elseif x == API.SQL_TYPE_DATE
        return (API.SQL_C_TYPE_DATE, Date)
    elseif x == API.SQL_TYPE_TIMESTAMP
        return (API.SQL_C_TYPE_TIMESTAMP, DateTime)
    elseif x == API.SQL_TYPE_TIME
        return (API.SQL_C_TYPE_TIME, Time)
    elseif x == API.SQL_GUID
        return (API.SQL_C_GUID, UUID)
    else
        return (API.SQL_C_CHAR, String)
    end
end

const RESERVED = Set(["local", "global", "export", "let",
    "for", "struct", "while", "const", "continue", "import",
    "function", "if", "else", "try", "begin", "break", "catch",
    "return", "using", "baremodule", "macro", "finally",
    "module", "elseif", "end", "quote", "do"])

normalizename(name::Symbol) = name
function normalizename(name::String)::Symbol
    uname = strip(Unicode.normalize(name))
    id = Base.isidentifier(uname) ? uname : map(c->Base.is_id_char(c) ? c : '_', uname)
    cleansed = string((isempty(id) || !Base.is_id_start_char(id[1]) || id in RESERVED) ? "_" : "", id)
    return Symbol(replace(cleansed, r"(_)\1+"=>"_"))
end