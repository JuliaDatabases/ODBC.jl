"just a block of memory; T is the element type, `len` is total # of **bytes* pointed to, and `elsize` is size of each element"
type Block{T}
    ptr::Ptr{T}     # pointer to a block of memory
    len::UInt       # total # of bytes in block
    elsize::UInt    # size between elements in bytes
end

typealias CHARS Union{ODBC.API.SQLCHAR,ODBC.API.SQLWCHAR}

"""
Block allocator:
    -Takes an element type, and number of elements to allocate in a linear block
    -Optionally specify an extra dimension of elements that make up each element (i.e. container types)
"""
function Block{T}(::Type{T}, elements::Int, extradim::Integer=1)
    len = sizeof(T) * elements * extradim
    block = Block{T}(convert(Ptr{T},Libc.malloc(len)),len,sizeof(T) * extradim)
    return block
end

# copy `n` bytes of a block
function Block{T}(block::Block{T},n::Integer=block.len)
    block2 = Block{T}(convert(Ptr{T},Libc.malloc(n)),n,block.elsize)
    ccall(:memcpy, Void, (Ptr{T}, Ptr{T}, Csize_t), block2.ptr, block.ptr, n)
    return block2
end

free!(block::Block) = Libc.free(block.ptr)
"remove the .ptr from a Block"
zero!(block::Block) = (block.ptr = 0; return nothing)

# used for getting messages back from ODBC driver manager; SQLDrivers, SQLError, etc.
Base.string(block::Block{UInt8},  len::Integer) = utf8(block.ptr,len)
Base.string(block::Block{UInt16}, len::Integer) = utf16(block.ptr,len)
Base.string(block::Block{UInt32}, len::Integer) = utf32(block.ptr,len)

bytes2codeunits(::Type{UInt8},  bytes::ODBC.API.SQLLEN) = ifelse(bytes == ODBC.API.SQL_NULL_DATA, convert(ODBC.API.SQLLEN,0), bytes)
bytes2codeunits(::Type{UInt16}, bytes::ODBC.API.SQLLEN) = ifelse(bytes == ODBC.API.SQL_NULL_DATA, convert(ODBC.API.SQLLEN,0), bytes >> 1)
bytes2codeunits(::Type{UInt32}, bytes::ODBC.API.SQLLEN) = ifelse(bytes == ODBC.API.SQL_NULL_DATA, convert(ODBC.API.SQLLEN,0), bytes >> 2)

const DECZERO = Dec64(0)

cleanup!{T<:CHARS}(::Type{T}, block, other) = push!(other, block)
cleanup!(::Type{Vector{UInt8}}, block, other) = zero!(block)
cleanup!(::Type{Dec64}, block, other) = free!(block)

cast{T}(::Type{T}, ptr, len, own) = Data.PointerString(ptr, len)
cast(::Type{Vector{UInt8}}, ptr, len, own) = pointer_to_array(ptr, len, own)
cast(::Type{Dec64}, ptr, len, own) = len == 0 ? DECZERO : parse(Dec64, string(Data.PointerString(ptr, len)))

getfield{T}(jltype,block::Block{T}, row, ind) = unsafe_load(block.ptr, row)
getfield{T<:CHARS}(jltype, block::Block{T}, row, ind) = cast(jltype, block.ptr + block.elsize * (row-1), ODBC.bytes2codeunits(T,ind), false)

function booleanize!(ind::Vector{ODBC.API.SQLLEN},rows)
    new = Array(Bool, rows)
    @simd for i = 1:rows
        @inbounds new[i] = ind[i] == ODBC.API.SQL_NULL_DATA
    end
    return new
end
function booleanize!(ind::Vector{ODBC.API.SQLLEN},new::Vector{Bool},offset,len)
    @simd for i = 1:len
        @inbounds new[i+offset] = ind[i] == ODBC.API.SQL_NULL_DATA
    end
    return new
end

"""create a NullableVector from a Block that has bitstype/immutable data;
   we're passing ownership of the memory to Julia and zeroing out the ptr in `block`"""
function NullableArrays.NullableArray{T}(jltype, block::Block{T}, ind, rows, other)
    a = NullableArray(pointer_to_array(block.ptr, rows, true), booleanize!(ind,rows))
    zero!(block)
    return a
end

"create a NullableVector from a Block that has container-type or Dec64 data"
function NullableArrays.NullableArray{T<:CHARS}(jltype, block::Block{T}, ind, rows, other)
    values = Array(jltype, rows)
    cur = block.ptr
    elsize = block.elsize
    for row = 1:rows
        @inbounds values[row] = ODBC.cast(jltype, cur, ODBC.bytes2codeunits(T,ind[row]), true)
        cur += elsize
    end
    cleanup!(jltype, block, other)
    return NullableArray(values, booleanize!(ind,rows))
end

"fill a NullableVector by copying the data from a Block that has bitstype/immutable data"
# copy!(rb.columns[col],rb.indcols[col],data[col],r,rows,other)
function Base.copy!{T}(jltype, block::Block{T}, ind, dest::NullableVector, offset, len, other)
    ccall(:memcpy, Void, (Ptr{T}, Ptr{T}, Csize_t), pointer(dest.values) + offset * sizeof(T), block.ptr, len * sizeof(T))
    booleanize!(ind,dest.isnull,offset,len)
    return nothing
end

"fill a NullableVector by copying the data from a Block that has Dec64 data"
function Base.copy!{T<:CHARS}(::Type{Dec64}, block::Block{T}, ind, dest::NullableVector, offset, len, other)
    values = dest.values
    isnull = dest.isnull
    cur = block.ptr
    elsize = block.elsize
    for i = 1:len
        @inbounds values[i+offset] = cast(Dec64, cur, ODBC.bytes2codeunits(T,ind[i]), true)
        @inbounds isnull[i+offset] = ind[i] == ODBC.API.SQL_NULL_DATA
        cur += elsize
    end
    return nothing
end

"fill a NullableVector by copying the data from a Block that has container-type"
function Base.copy!{T<:CHARS}(jltype, block::Block{T}, ind, dest::NullableVector, offset, len, other)
    # basic strategy is:
      # make our own copy of the memory
      # loop over elsize and create PointerString(cur_ptr, ind[row])
      # add our copy of the memory block to a ref array that gets saved in the Data.Table
    block2 = ODBC.Block(block, len == 1 ? max(0,ind[1]) : block.len)
    values = dest.values
    isnull = dest.isnull
    cur = block2.ptr
    elsize = block2.elsize
    for i = 1:len
        @inbounds values[i+offset] = cast(jltype, cur, ODBC.bytes2codeunits(T,ind[i]), true)
        @inbounds isnull[i+offset] = ind[i] == ODBC.API.SQL_NULL_DATA
        cur += elsize
    end
    cleanup!(jltype, block2, other)
    return nothing
end

"append to a NullableVector by copying the data from a Block that has bitstype/immutable data"
function Base.append!{T}(jltype, block::Block{T}, ind, dest::NullableVector, offset, len, other)
    ccall(:jl_array_grow_end, Void, (Any, UInt), dest.values, len)
    ccall(:memcpy, Void, (Ptr{T}, Ptr{T}, Csize_t), pointer(dest.values) + offset * sizeof(T), block.ptr, len * sizeof(T))
    ccall(:jl_array_grow_end, Void, (Any, UInt), dest.isnull, len)
    booleanize!(ind,dest.isnull,offset,len)
    return nothing
end

"append to a NullableVector by copying the data from a Block that has container-type data"
function Base.append!{T<:CHARS}(::Type{Dec64}, block::Block{T}, ind, dest::NullableVector, offset, len, other)
    values = dest.values
    isnull = dest.isnull
    ccall(:jl_array_grow_end, Void, (Any, UInt), values, len)
    ccall(:jl_array_grow_end, Void, (Any, UInt), isnull, len)
    cur = block.ptr
    elsize = block.elsize
    for i = 1:len
        @inbounds values[i+offset] = cast(Dec64, cur, ODBC.bytes2codeunits(T,ind[i]), true)
        @inbounds isnull[i+offset] = ind[i] == ODBC.API.SQL_NULL_DATA
        cur += elsize
    end
    return nothing
end

"append to a NullableVector by copying the data from a Block that has container-type data"
function Base.append!{T<:CHARS}(jltype, block::Block{T}, ind, dest::NullableVector, offset, len, other)
    values = dest.values
    isnull = dest.isnull
    ccall(:jl_array_grow_end, Void, (Any, UInt), values, len)
    ccall(:jl_array_grow_end, Void, (Any, UInt), isnull, len)
    block2 = ODBC.Block(block, len == 1 ? max(0,ind[1]) : block.len)
    cur = block2.ptr
    elsize = block2.elsize
    for i = 1:len
        @inbounds values[i+offset] = cast(jltype, cur, ODBC.bytes2codeunits(T,ind[i]), true)
        @inbounds isnull[i+offset] = ind[i] == ODBC.API.SQL_NULL_DATA
        cur += elsize
    end
    cleanup!(jltype, block2, other)
    return nothing
end
