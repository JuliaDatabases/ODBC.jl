
using StaticArrays

struct GUID
    data1:: Cuint;
    data2:: Cushort;
    data3:: Cushort;
    data4:: SVector{8, Cuchar};
end

Base.zero(::Type{GUID}) = GUID(0,0,0,zero(SVector{8, Cuchar}))

# This is hijacking!
Base.zero(::Type{Base.UUID}) = Base.UUID(0)

# function trivialprint(io::IO, g::GUID)
#     hex(n) = string(n, base=16, pad=2) ;
#     print(io, hex(g.data1));
#     print(io, "-");
#     print(io, hex(g.data2));
#     print(io, "-");
#     print(io, hex(g.data3));
#     print(io, "-");
#     print(io, hex(g.data4[1]));
#     print(io, hex(g.data4[2]));
#     print(io, "-");
#     print(io, hex(g.data4[3]));
#     print(io, hex(g.data4[4]));
#     print(io, hex(g.data4[5]));
#     print(io, hex(g.data4[6]));
#     print(io, hex(g.data4[7]));
#     print(io, hex(g.data4[8]));
# end

# Approach for converting to string following somewhat that in Base.UUID
# Code written in a way that was easy for me to understand.

const hex_chars = UInt8['0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
                        'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i',
                        'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r',
                        's', 't', 'u', 'v', 'w', 'x', 'y', 'z']

function GUID(u::Base.UUID) 
    g = zero(MVector{16, UInt8})
    inuuid = reinterpret(NTuple{16, UInt8}, u)

    ix = [13;14;15;16;11;12;9;10;8;7;6;5;4;3;2;1]

    for (to, from) in enumerate(ix)
        g[to] = inuuid[from]
    end

    return reinterpret(GUID, NTuple{16, UInt8}(g))
end

function Base.convert(::Type{Base.UUID}, g::GUID) 
    u = zero(MVector{16, UInt8})
    inguid = reinterpret(NTuple{16, UInt8}, g)

    ix = [13;14;15;16;11;12;9;10;8;7;6;5;4;3;2;1]

    for (from, to) in enumerate(ix)
        u[to] = inguid[from]
    end

    return reinterpret(Base.UUID, NTuple{16, UInt8}(u))
end
#was previously    Base.UUID(Base.string(g))


Base.convert(::Type{String}, g::GUID) = Base.string(g)
Base.convert(::Type{UInt128}, g::GUID) = Base.UUID(Base.string(g)).value

function Base.string(g::GUID)
    a = Base.StringVector(36)
    u = g.data1
    for i in [8:-1:1;]
        a[i] = hex_chars[1 + u & 0xf]
        u >>= 4
    end
    u = g.data2
    for i in [13:-1:10;]
        a[i] = hex_chars[1 + u & 0xf]
        u >>= 4
    end
    u = g.data3
    for i in [18:-1:15;]
        a[i] = hex_chars[1 + u & 0xf]
        u >>= 4
    end

    u = g.data4[1]
    for i in [21:-1:20;]
        a[i] = hex_chars[1 + u & 0xf]
        u >>= 4
    end
    u = g.data4[2]
    for i in [23:-1:22;]
        a[i] = hex_chars[1 + u & 0xf]
        u >>= 4
    end

    u = g.data4[3]
    for i in [26:-1:25;]
        a[i] = hex_chars[1 + u & 0xf]
        u >>= 4
    end
    u = g.data4[4]
    for i in [28:-1:27;]
        a[i] = hex_chars[1 + u & 0xf]
        u >>= 4
    end
    u = g.data4[5]
    for i in [30:-1:29;]
        a[i] = hex_chars[1 + u & 0xf]
        u >>= 4
    end
    u = g.data4[6]
    for i in [32:-1:31;]
        a[i] = hex_chars[1 + u & 0xf]
        u >>= 4
    end
    u = g.data4[7]
    for i in [34:-1:33;]
        a[i] = hex_chars[1 + u & 0xf]
        u >>= 4
    end
    u = g.data4[8]
    for i in [36:-1:35;]
        a[i] = hex_chars[1 + u & 0xf]
        u >>= 4
    end
    
    a[24] = a[19] = a[14] = a[9] = '-'
    return String(a)
end
