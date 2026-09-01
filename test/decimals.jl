using Test, ODBC, Decimals

const API = ODBC.API

# a char-fetch column buffer: `elsize` bytes per row, plus the indicator vector
function charcolumn(strs, elsize)
    data = fill(0x00, elsize * length(strs))
    inds = Vector{Int}(undef, length(strs))
    for (j, s) in enumerate(strs)
        if s === missing
            inds[j] = API.SQL_NULL_DATA
        else
            bytes = codeunits(s)
            copyto!(data, (j - 1) * elsize + 1, bytes, 1, length(bytes))
            inds[j] = length(bytes)
        end
    end
    return data, inds
end

@testset "decimaltype tiers" begin
    @test ODBC.storageint(1) === Int32
    @test ODBC.storageint(9) === Int32
    @test ODBC.storageint(10) === Int64
    @test ODBC.storageint(18) === Int64
    @test ODBC.storageint(19) === Int128
    @test ODBC.storageint(38) === Int128
    @test ODBC.storageint(39) === ODBC.DECIMAL_INT256
    @test ODBC.storageint(76) === ODBC.DECIMAL_INT256
    @test ODBC.decimaltype(5, 3) === Decimal{5, 3, Int32}
    @test ODBC.decimaltype(18, 18) === Decimal{18, 18, Int64}
    @test ODBC.decimaltype(20, 2) === Decimal{20, 2, Int128}
    @test ODBC.decimaltype(65, 30) === Decimal{65, 30, ODBC.DECIMAL_INT256}
    @test ODBC.decimaltype(76, 0) === Decimal{76, 0, ODBC.DECIMAL_INT256}
    # unrepresentable or unusable metadata falls back to lossless String
    @test ODBC.decimaltype(77, 0) === String
    @test ODBC.decimaltype(0, 0) === String
    @test ODBC.decimaltype(-1, 0) === String
    @test ODBC.decimaltype(5, 6) === String
    @test ODBC.decimaltype(5, -1) === String
end

@testset "fetchtypes for DECIMAL/NUMERIC" begin
    for sqltype in (API.SQL_DECIMAL, API.SQL_NUMERIC)
        @test ODBC.fetchtypes(sqltype, 5, 3) == (API.SQL_C_CHAR, Decimal{5, 3, Int32})
        @test ODBC.fetchtypes(sqltype, 20, 2) == (API.SQL_C_CHAR, Decimal{20, 2, Int128})
        @test ODBC.fetchtypes(sqltype, 65, 4) == (API.SQL_C_CHAR, Decimal{65, 4, ODBC.DECIMAL_INT256})
        @test ODBC.fetchtypes(sqltype, 0, 0) == (API.SQL_C_CHAR, String)
        # a driver reporting an unsigned garbage column size must not throw
        @test ODBC.fetchtypes(sqltype, typemax(UInt64), 0) == (API.SQL_C_CHAR, String)
    end
    @test ODBC.fetchtypes(API.SQL_INTEGER, 10, 0) == (API.SQL_C_SLONG, Int32)
    @test ODBC.fetchtypes(API.SQL_VARCHAR, 255, 0) == (API.SQL_C_CHAR, String)
end

@testset "jlcast from the character buffer" begin
    D = Decimal{5, 3, Int32}
    @test ODBC.jlcast(D, b"1.001") == parse(D, "1.001")
    @test ODBC.jlcast(D, b"-1.001") == parse(D, "-1.001")
    @test ODBC.jlcast(D, b"+1.001") == parse(D, "1.001")
    @test ODBC.jlcast(D, b"00001.0010") == parse(D, "1.001")
    @test ODBC.jlcast(D, b"1") == parse(D, "1")
    @test ODBC.jlcast(D, b"  2.5  ") == parse(D, "2.5")
    @test ODBC.jlcast(D, b"1.001\0\0") == parse(D, "1.001")
    @test ODBC.jlcast(D, b"1001e-3") == parse(D, "1.001")
    @test ODBC.jlcast(D, b"-99.999") == parse(D, "-99.999")
    # extra fractional digits round half-even at the column scale
    @test ODBC.jlcast(D, b"1.0015") == parse(D, "1.002")
    @test ODBC.jlcast(D, b"1.0025") == parse(D, "1.002")
    # the 128- and 256-bit tiers keep every digit
    D128 = Decimal{20, 2, Int128}
    @test ODBC.jlcast(D128, b"123456789012345678.91") == parse(D128, "123456789012345678.91")
    D256 = Decimal{65, 30, ODBC.DECIMAL_INT256}
    wide = "-12345678901234567890123456789012345.123456789012345678901234567890"
    @test ODBC.jlcast(D256, codeunits(wide)) == parse(D256, wide)
    @test ODBC.jlcast(DecimalValue{Int128}, b"-1.001") == DecimalValue{Int128}(-1001, 3)
    @test_throws ArgumentError ODBC.jlcast(D, b"not a number")
    @test_throws OverflowError ODBC.jlcast(D, b"1000.001")
end

@testset "column decoding" begin
    D = Decimal{5, 3, Int32}
    T = Union{Missing, D}
    # the character form of DECIMAL(5,3) needs 5 digits + sign + point + NUL
    elsize = 5 + 3
    data, inds = charcolumn(["1.001", "-2.500", missing, "99.999"], elsize)
    col = ODBC.decodechars(T, data, inds, 4, elsize)
    @test col isa Vector{T}
    @test isequal(col, T[parse(D, "1.001"), parse(D, "-2.5"), missing, parse(D, "99.999")])
    # non-nullable columns decode to the bare type
    data, inds = charcolumn(["1.001", "2.002"], elsize)
    @test ODBC.decodechars(D, data, inds, 2, elsize) == D[parse(D, "1.001"), parse(D, "2.002")]
    # decoding is specialized on the column type, so the loop body is type-stable
    @test (@inferred ODBC.decodechars(D, data, inds, 2, elsize)) == D[parse(D, "1.001"), parse(D, "2.002")]
end

@testset "decimal parameter binding" begin
    D = Decimal{5, 3, Int32}
    x = parse(D, "-1.001")
    @test ODBC.bindtypes(x) == (API.SQL_C_CHAR, API.SQL_DECIMAL)
    @test ODBC.bindtypes(DecimalValue{Int128}(-1001, 3)) == (API.SQL_C_CHAR, API.SQL_DECIMAL)
    @test ODBC.ccast(x) == "-1.001"
    @test ODBC.ccast(DecimalValue{Int128}(-1001, 3)) == "-1.001"
    @test !ODBC.needswrapped(x)
    b = ODBC.Buffer(x)
    @test b.buffer == "-1.001"
    @test ODBC.bufferlength(b) == 6
    @test ODBC.columnsize(b) == 6
    # rebinding a new value in place
    ODBC.update!(b, parse(D, "2.5"))
    @test b.buffer == "2.500"
    ODBC.update!(b, missing)
    @test b.buffer === ODBC.MISSING_BUF
end
