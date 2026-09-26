module GetDataTests

using Test, ODBC
const API = ODBC.API

mutable struct ChunkStatement
    bytes::Union{Missing,Vector{UInt8}}
    unknown::Bool
    warning::Bool
    offset::Int
    calls::Vector{Tuple{Int,Int,Int}}
    failat::Int
    failure::API.SQLRETURN
    poison::Int
end
ChunkStatement(bytes; unknown=true, warning=false, failat=0,
    failure=API.SQL_ERROR, poison=-99) =
    ChunkStatement(bytes, unknown, warning, 0, Tuple{Int,Int,Int}[], failat, failure, poison)

API.getptr(stmt::ChunkStatement) = stmt
API.diagnostics(::ChunkStatement) = "HY000: injected SQLGetData failure"

# A test-owned statement implements the driver contract, without replacing the
# methods that call real ODBC drivers. Only truncation reports SQL_NO_TOTAL.
function API.SQLGetData(stmt::ChunkStatement, column, ctype, target, capacity, indicator)
    call = length(stmt.calls) + 1
    call <= 32 || error("test exceeded its SQLGetData call bound")
    variable = ctype in (API.SQL_C_CHAR, API.SQL_C_WCHAR, API.SQL_C_BINARY)
    if variable
        # Keep even unused output bytes deterministic when checking a reader
        # that incorrectly counts padding or a failed call as returned data.
        for j in 1:capacity
            unsafe_store!(Ptr{UInt8}(target), 0xa5, j)
        end
    end
    if call == stmt.failat
        # Failed and SQL_NO_DATA calls leave outputs undefined. Poisoning the
        # indicator exposes an invalid read without using uninitialized memory.
        indicator[1] = stmt.poison
        push!(stmt.calls, (capacity, stmt.failure, indicator[1]))
        return stmt.failure
    elseif ismissing(stmt.bytes)
        indicator[1] = API.SQL_NULL_DATA
        push!(stmt.calls, (capacity, API.SQL_SUCCESS, indicator[1]))
        return API.SQL_SUCCESS
    elseif call > 1 && stmt.offset == length(stmt.bytes)
        indicator[1] = stmt.poison
        push!(stmt.calls, (capacity, API.SQL_NO_DATA, indicator[1]))
        return API.SQL_NO_DATA
    end
    terminator = ctype == API.SQL_C_CHAR ? 1 :
        ctype == API.SQL_C_WCHAR ? sizeof(API.sqlwcharsize()) : 0
    remaining = length(stmt.bytes) - stmt.offset
    space = max(0, capacity - terminator)
    terminator > 1 && (space -= space % terminator)
    fetched = variable ? min(remaining, space) : remaining
    bytes = stmt.bytes
    GC.@preserve bytes begin
        fetched == 0 || unsafe_copyto!(Ptr{UInt8}(target), pointer(bytes, stmt.offset + 1), fetched)
    end
    if capacity >= terminator
        for j in 1:terminator
            unsafe_store!(Ptr{UInt8}(target), 0x00, fetched + j)
        end
    end
    stmt.offset += fetched
    truncated = fetched < remaining
    indicator[1] = truncated && stmt.unknown ? API.SQL_NO_TOTAL : remaining
    status = truncated || stmt.warning ? API.SQL_SUCCESS_WITH_INFO : API.SQL_SUCCESS
    push!(stmt.calls, (capacity, status, indicator[1]))
    return status
end

function binding(stmt, ctype, capacity=256; long=true)
    b = ODBC.Binding(stmt, false, 1, ctype, API.SQL_LONGVARBINARY, capacity,
        API.SQL_NO_NULLS, long, 1)
    fill!(b.value.buffer, zero(eltype(b.value.buffer)))
    fill!(b.strlen_or_indptr, -88)
    return b
end

function payload(n, ctype)
    if ctype == API.SQL_C_WCHAR
        T = API.sqlwcharsize()
        return collect(reinterpret(UInt8, T[isodd(i) ? 0x2665 : 0 for i in 1:(n ÷ sizeof(T))]))
    end
    return UInt8[mod(i * 37, ctype == API.SQL_C_BINARY ? 256 : 127) for i in 1:n]
end

@testset "SQLGetData chunks" begin
    for ctype in (API.SQL_C_BINARY, API.SQL_C_CHAR, API.SQL_C_WCHAR),
        capacity in (8, 256), unknown in (false, true), warning in (false, true),
        long in (false, true)
        width = ctype == API.SQL_C_WCHAR ? sizeof(API.sqlwcharsize()) : 1
        terminator = ctype == API.SQL_C_BINARY ? 0 : width
        for n in unique((0, width, capacity - terminator, capacity, capacity + width,
            2 * capacity - terminator, 2 * capacity, 2 * capacity + width, 4 * capacity))
            expected = payload(n, ctype)
            stmt = ChunkStatement(expected; unknown, warning)
            b = binding(stmt, ctype, capacity; long)
            ODBC.getdata(stmt, 1, b)
            @test b.totallen == n
            @test b.value.buffer[1:b.totallen] == expected
            @test stmt.offset == n
            # A complete SQL_SUCCESS_WITH_INFO warning does not request more
            # data, even when binary data exactly fills the supplied buffer.
            @test all(call -> call[2] != API.SQL_NO_DATA, stmt.calls)
        end
    end

    @testset "fixed-width warning" begin
        for (ctype, value) in ((API.SQL_C_SLONG, Int32(42)),
            (API.SQL_C_TYPE_DATE, API.SQLDate(ODBC.Dates.Date(2020, 1, 2))))
            expected = collect(reinterpret(UInt8, [value]))
            stmt = ChunkStatement(expected; warning=true)
            # BufferLength is ignored for fixed-width C targets.
            b = binding(stmt, ctype, 1; long=false)
            ODBC.getdata(stmt, 1, b)
            @test collect(reinterpret(UInt8, b.value.buffer)) == expected
            @test b.totallen == sizeof(value)
            @test length(stmt.calls) == 1
        end
    end

    @testset "NULL and reused storage" begin
        for ctype in (API.SQL_C_BINARY, API.SQL_C_CHAR, API.SQL_C_WCHAR)
            b = binding(nothing, ctype)
            for value in (payload(1024, ctype), missing, UInt8[], payload(8, ctype))
                stmt = ChunkStatement(value)
                ODBC.getdata(stmt, 1, b)
                if ismissing(value)
                    @test b.strlen_or_indptr[1] == API.SQL_NULL_DATA
                    @test b.totallen == API.SQL_NULL_DATA
                else
                    @test b.totallen == length(value)
                    @test b.value.buffer[1:b.totallen] == value
                end
            end
        end
    end

    @testset "undefined outputs and recovery" begin
        for status in (API.SQL_ERROR, API.SQL_INVALID_HANDLE, API.SQL_NO_DATA, API.SQL_STILL_EXECUTING),
            failat in (1, 2), unknown in (false, true), poison in (-99, 42)
            stmt = ChunkStatement(payload(1024, API.SQL_C_BINARY);
                failat, failure=status, unknown, poison)
            b = binding(stmt, API.SQL_C_BINARY)
            err = try
                ODBC.getdata(stmt, 1, b)
                nothing
            catch e
                e
            end
            @test err isa ErrorException
            @test length(stmt.calls) == failat
            @test b.totallen == (failat == 1 ? 0 : 256)
            if status in (API.SQL_ERROR, API.SQL_INVALID_HANDLE)
                @test sprint(showerror, err) == "HY000: injected SQLGetData failure"
            end
            # The same binding must start the next value from byte zero.
            expected = UInt8[0x00, 0xff, 0x00]
            ODBC.getdata(ChunkStatement(expected), 1, b)
            @test b.totallen == length(expected)
            @test b.value.buffer[1:b.totallen] == expected
        end
    end
end

end
