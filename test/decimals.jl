using Test, ODBC, Decimals, Libdl, unixODBC_jll
@static if !Sys.iswindows()
    using iODBC_jll
end

const API = ODBC.API

# build a SQL_NUMERIC_STRUCT the way a driver would: 16-byte little-endian
# unscaled coefficient, sign 1 == positive / 0 == negative
function sqlnumeric(unscaled::Integer, precision::Integer, scale::Integer)
    u = Int128(unscaled)
    neg = u < 0
    mag = neg ? UInt128(-u) : UInt128(u)
    val = ntuple(i -> UInt8((mag >> (8 * (i - 1))) & 0xff), API.SQL_MAX_NUMERIC_LEN)
    return API.SQLNumeric(UInt8(precision), Int8(scale), UInt8(neg ? 0 : 1), val)
end

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

@testset "SQLNumeric struct" begin
    @test sizeof(API.SQLNumeric) == 19
    z = zero(API.SQLNumeric)
    @test API.magnitude(z) == 0
    @test z.sign == 1
    @test length(z.val) == API.SQL_MAX_NUMERIC_LEN
    # little-endian: byte i is bits 8(i-1)..8i-1
    x = sqlnumeric(Int128(0x0102030405060708), 20, 0)
    @test x.val[1] == 0x08
    @test x.val[8] == 0x01
    @test API.magnitude(x) == 0x0102030405060708
    @test API.magnitude(sqlnumeric(typemax(Int128), 39, 0)) == UInt128(typemax(Int128))
    # sign lives outside val, so the magnitude bytes are identical
    @test sqlnumeric(-12345, 5, 3).val == sqlnumeric(12345, 5, 3).val
    @test sqlnumeric(-12345, 5, 3).sign == 0
    @test sqlnumeric(12345, 5, 3).sign == 1
end

@testset "decimalfromnumeric" begin
    D = Decimal{5, 3, Int32}
    @test ODBC.decimalfromnumeric(D, sqlnumeric(1001, 5, 3)) == D("1.001")
    @test ODBC.decimalfromnumeric(D, sqlnumeric(-2500, 5, 3)) == D("-2.5")
    @test ODBC.decimalfromnumeric(D, sqlnumeric(0, 5, 3)) == zero(D)
    @test ODBC.decimalfromnumeric(D, sqlnumeric(-99999, 5, 3)) == D("-99.999")
    # scale == precision, and scale == 0
    @test ODBC.decimalfromnumeric(Decimal{5, 5, Int32}, sqlnumeric(-99999, 5, 5)) == Decimal{5, 5, Int32}("-0.99999")
    @test ODBC.decimalfromnumeric(Decimal{5, 0, Int32}, sqlnumeric(99999, 5, 0)) == Decimal{5, 0, Int32}("99999")
    # widest digit counts each storage tier holds
    @test ODBC.decimalfromnumeric(Decimal{9, 0, Int32}, sqlnumeric(999999999, 9, 0)) == Decimal{9, 0, Int32}("999999999")
    @test ODBC.decimalfromnumeric(Decimal{18, 0, Int64}, sqlnumeric(-999999999999999999, 18, 0)) == Decimal{18, 0, Int64}("-999999999999999999")
    big38 = Int128(10)^38 - 1
    @test ODBC.decimalfromnumeric(Decimal{38, 0, Int128}, sqlnumeric(big38, 38, 0)) == Decimal{38, 0, Int128}("99999999999999999999999999999999999999")
    @test ODBC.decimalfromnumeric(Decimal{38, 38, Int128}, sqlnumeric(-big38, 38, 38)) == Decimal{38, 38, Int128}("-0.99999999999999999999999999999999999999")
    # driver ignored our requested scale: exact rescales work either way
    @test ODBC.decimalfromnumeric(D, sqlnumeric(1, 5, 0)) == D("1")
    @test ODBC.decimalfromnumeric(D, sqlnumeric(10010, 6, 4)) == D("1.001")
    # ...but one that would drop a nonzero digit is an error, not silent loss
    @test_throws InexactError ODBC.decimalfromnumeric(D, sqlnumeric(10011, 6, 4))
    # negative scale means trailing implicit zeros
    @test ODBC.decimalfromnumeric(Decimal{9, 2, Int32}, sqlnumeric(5, 9, -2)) == Decimal{9, 2, Int32}("500")
    # coefficient too wide for the target type
    @test_throws OverflowError ODBC.decimalfromnumeric(Decimal{9, 0, Int32}, sqlnumeric(big38, 38, 0))
    # a coefficient above typemax(Int128) can't be a valid <= 38 digit decimal
    allones = API.SQLNumeric(0x26, Int8(0), 0x01, ntuple(_ -> 0xff, API.SQL_MAX_NUMERIC_LEN))
    @test_throws InexactError ODBC.decimalfromnumeric(Decimal{38, 0, Int128}, allones)
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
        @test ODBC.fetchtypes(sqltype, 5, 3, false) == (API.SQL_C_CHAR, Decimal{5, 3, Int32})
        @test ODBC.fetchtypes(sqltype, 20, 2, false) == (API.SQL_C_CHAR, Decimal{20, 2, Int128})
        @test ODBC.fetchtypes(sqltype, 65, 4, false) == (API.SQL_C_CHAR, Decimal{65, 4, ODBC.DECIMAL_INT256})
        @test ODBC.fetchtypes(sqltype, 0, 0, false) == (API.SQL_C_CHAR, String)
        # a driver reporting an unsigned garbage column size must not throw
        @test ODBC.fetchtypes(sqltype, typemax(UInt64), 0, false) == (API.SQL_C_CHAR, String)
        # struct binding only where a 16-byte coefficient suffices
        @test ODBC.fetchtypes(sqltype, 5, 3, true) == (API.SQL_C_NUMERIC, Decimal{5, 3, Int32})
        @test ODBC.fetchtypes(sqltype, 38, 10, true) == (API.SQL_C_NUMERIC, Decimal{38, 10, Int128})
        @test ODBC.fetchtypes(sqltype, 39, 10, true) == (API.SQL_C_CHAR, Decimal{39, 10, ODBC.DECIMAL_INT256})
        @test ODBC.fetchtypes(sqltype, 0, 0, true) == (API.SQL_C_CHAR, String)
    end
    # other types are unaffected by the numeric binding mode
    @test ODBC.fetchtypes(API.SQL_INTEGER, 10, 0, true) == (API.SQL_C_SLONG, Int32)
    @test ODBC.fetchtypes(API.SQL_VARCHAR, 255, 0, true) == (API.SQL_C_CHAR, String)
end

@testset "numeric_binding validation" begin
    @test ODBC.checknumericbinding(:char) === false
    @test ODBC.checknumericbinding(:struct) === true
    @test_throws ArgumentError ODBC.checknumericbinding(:numeric)
    # the struct path needs a live driver to exercise, but the entry points it
    # ccalls can be checked against the driver managers we ship
    if !Sys.iswindows()
        for lib in (iODBC_jll.libiodbc, unixODBC_jll.libodbc)
            h = Libdl.dlopen(lib)
            @test Libdl.dlsym(h, :SQLGetStmtAttrW; throw_error=false) !== nothing
            @test Libdl.dlsym(h, :SQLSetDescField; throw_error=false) !== nothing
        end
    end
end

@testset "jlcast from the character buffer" begin
    D = Decimal{5, 3, Int32}
    @test ODBC.jlcast(D, b"1.001") == D("1.001")
    @test ODBC.jlcast(D, b"-1.001") == D("-1.001")
    @test ODBC.jlcast(D, b"+1.001") == D("1.001")
    @test ODBC.jlcast(D, b"00001.0010") == D("1.001")
    @test ODBC.jlcast(D, b"1") == D("1")
    @test ODBC.jlcast(D, b"  2.5  ") == D("2.5")
    @test ODBC.jlcast(D, b"1.001\0\0") == D("1.001")
    @test ODBC.jlcast(D, b"1001e-3") == D("1.001")
    @test ODBC.jlcast(D, b"-99.999") == D("-99.999")
    # extra fractional digits round half-even at the column scale
    @test ODBC.jlcast(D, b"1.0015") == D("1.002")
    @test ODBC.jlcast(D, b"1.0025") == D("1.002")
    # the 128- and 256-bit tiers keep every digit
    D128 = Decimal{20, 2, Int128}
    @test ODBC.jlcast(D128, b"123456789012345678.91") == D128("123456789012345678.91")
    D256 = Decimal{65, 30, ODBC.DECIMAL_INT256}
    wide = "-12345678901234567890123456789012345.123456789012345678901234567890"
    @test ODBC.jlcast(D256, codeunits(wide)) == D256(wide)
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
    @test isequal(col, T[D("1.001"), D("-2.5"), missing, D("99.999")])
    # non-nullable columns decode to the bare type
    data, inds = charcolumn(["1.001", "2.002"], elsize)
    @test ODBC.decodechars(D, data, inds, 2, elsize) == D[D("1.001"), D("2.002")]
    # and the same resultset through the struct path
    nums = Union{Missing, API.SQLNumeric}[sqlnumeric(1001, 5, 3), sqlnumeric(-2500, 5, 3), zero(API.SQLNumeric), sqlnumeric(99999, 5, 3)]
    ninds = [8, 8, API.SQL_NULL_DATA, 8]
    col2 = ODBC.decodenumerics(T, nums, ninds, 4)
    @test col2 isa Vector{T}
    @test isequal(col2, col)
    # decoding is specialized on the column type, so the loop body is type-stable
    @test (@inferred ODBC.decodenumerics(D, API.SQLNumeric[sqlnumeric(1001, 5, 3)], [8], 1)) == D[D("1.001")]
    @test (@inferred ODBC.decodechars(D, data, inds, 2, elsize)) == D[D("1.001"), D("2.002")]
end

@testset "numeric fetch buffers" begin
    b = ODBC.Buffer(API.SQL_C_NUMERIC, 5, 4, API.SQL_NO_NULLS)
    @test b.buffer isa Vector{API.SQLNumeric}
    @test length(b.buffer) == 4
    @test pointer(b) == pointer(b.buffer)
    nb = ODBC.Buffer(API.SQL_C_NUMERIC, 5, 4, Int16(1))
    @test nb.buffer isa Vector{Union{Missing, API.SQLNumeric}}
    @test all(==(zero(API.SQLNumeric)), nb.buffer)
    @test pointer(nb) !== C_NULL
end

@testset "decimal parameter binding" begin
    D = Decimal{5, 3, Int32}
    x = D("-1.001")
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
    ODBC.update!(b, D("2.5"))
    @test b.buffer == "2.500"
    ODBC.update!(b, missing)
    @test b.buffer === ODBC.MISSING_BUF
end
