"just a block of memory that will be `free`d when we're done with it; T is the element type and N is the size of each element"
type Block{T}
    ptr::Ptr{T}     # pointer to a block of memory
    len::UInt       # total # of bytes in block
    elsize::UInt    # size between elements in bytes
end

typealias CHARS Union{ODBC.API.SQLCHAR,ODBC.API.SQLWCHAR}

function Block{T}(::Type{T}, elements::Int, finalize::Bool=true)
    len = sizeof(T) * elements
    block = Block{T}(convert(Ptr{T},Libc.malloc(len)),len,sizeof(T))
    finalize && finalizer(block,x->Libc.free(x.ptr))
    return block
end

# column allocators
# bitstype/immutables
function Block{T}(::Type{T}, sz::Integer, rows::Int, finalize::Bool=true)
    len = sizeof(T) * rows
    block = Block{T}(convert(Ptr{T},Libc.malloc(len)),len,sizeof(T))
    finalize && finalizer(block,x->Libc.free(x.ptr))
    return block
end
# container types; i.e. strings
function Block{T<:CHARS}(::Type{T}, sz::Integer, rows::Int, finalize::Bool=true)
    len = sizeof(T) * sz * rows
    block = Block{T}(convert(Ptr{T},Libc.malloc(len)),len,sizeof(T) * sz)
    finalize && finalizer(block,x->Libc.free(x.ptr))
    return block
end
# copy a block
function Block{T}(block::Block{T}, finalize::Bool=true)
    block2 = Block{T}(convert(Ptr{T},Libc.malloc(block.len)),block.len,block.elsize)
    finalize && finalizer(block2,x->Libc.free(x.ptr))
    ccall(:memcpy, Void, (Ptr{T}, Ptr{T}, Csize_t), block2.ptr, block.ptr, block.len)
    return block2
end

Base.string(block::Block{UInt8},  len::Integer) = utf8(block.ptr,len)
Base.string(block::Block{UInt16}, len::Integer) = utf16(block.ptr,len)
Base.string(block::Block{UInt32}, len::Integer) = utf32(block.ptr,len)
Base.string(block::Block{UInt8}) = utf8(block.ptr)
Base.string(block::Block{UInt16}) = utf16(block.ptr)
Base.string(block::Block{UInt32}) = utf32(block.ptr)

getfield{T}(block::Block{T}, row, ind) = unsafe_load(block.ptr, row)

function getfield{T<:CHARS}(block::Block{T}, row, ind)
    return Data.PointerString(block.ptr + block.elsize * (row-1), ODBC.bytes2codeunits(T,ind))
end

function booleanize!(ind::Vector{ODBC.API.SQLLEN})
    len = length(ind)
    new = Array(Bool, len)
    @simd for i = 1:len
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

"create a NullableVector from a Block that has bitstype/immutable data"
NullableArrays.NullableArray{T}(block::Block{T}, ind, rows, other) = NullableArray(pointer_to_array(block.ptr, rows, true), booleanize!(ind))

bytes2codeunits(::Type{UInt8},  bytes::ODBC.API.SQLLEN) = ifelse(bytes == ODBC.API.SQL_NULL_DATA, convert(ODBC.API.SQLLEN,0), bytes)
bytes2codeunits(::Type{UInt16}, bytes::ODBC.API.SQLLEN) = ifelse(bytes == ODBC.API.SQL_NULL_DATA, convert(ODBC.API.SQLLEN,0), bytes >> 1)
bytes2codeunits(::Type{UInt32}, bytes::ODBC.API.SQLLEN) = ifelse(bytes == ODBC.API.SQL_NULL_DATA, convert(ODBC.API.SQLLEN,0), bytes >> 2)

"create a NullableVector from a Block that has container-type data"
function NullableArrays.NullableArray{T<:CHARS}(block::Block{T}, ind, rows, other)
    values = Array(Data.PointerString{T}, rows)
    cur = block.ptr
    elsize = block.elsize
    for row = 1:rows
        @inbounds values[row] = Data.PointerString(cur, bytes2codeunits(T,ind[row]))
        cur += elsize
    end
    push!(other, block)
    return NullableArray(values, booleanize!(ind))
end

"fill a NullableVector by copying the data from a Block that has bitstype/immutable data"
# copy!(rb.columns[col],rb.indcols[col],data[col],r,rows,other)
function Base.copy!{T}(block::Block{T}, ind, dest::NullableVector, offset, len, other)
    ccall(:memcpy, Void, (Ptr{T}, Ptr{T}, Csize_t), pointer(dest.values) + offset * sizeof(T), block.ptr, len * sizeof(T))
    booleanize!(ind,dest.isnull,offset,len)
    return nothing
end
"append to a NullableVector by copying the data from a Block that has bitstype/immutable data"
function Base.append!{T}(block::Block{T}, ind, dest::NullableVector, offset, len, other)
    ccall(:jl_array_grow_end, Void, (Any, UInt), dest.values, len)
    ccall(:memcpy, Void, (Ptr{T}, Ptr{T}, Csize_t), pointer(dest.values) + offset * sizeof(T), block.ptr, len * sizeof(T))
    ccall(:jl_array_grow_end, Void, (Any, UInt), dest.isnull, len)
    booleanize!(ind,dest.isnull,offset,len)
    return nothing
end
"fill a NullableVector by copying the data from a Block that has container-type data"
function Base.copy!{T<:CHARS}(block::Block{T}, ind, dest::NullableVector, offset, len, other)
    # basic strategy is:
      # make our own copy of the memory
      # loop over elsize and create PointerString(cur_ptr, ind[row])
      # add our copy of the memory block to a ref array that gets saved in the Data.Table
    block2 = Block(block)
    values = dest.values
    isnull = dest.isnull
    cur = block2.ptr
    elsize = block2.elsize
    for i = 1:len
        @inbounds values[i+offset] = Data.PointerString(cur, bytes2codeunits(T,ind[i]))
        @inbounds isnull[i+offset] = ind[i] == ODBC.API.SQL_NULL_DATA
        cur += elsize
    end
    push!(other,block2)
    return nothing
end
"append to a NullableVector by copying the data from a Block that has container-type data"
function Base.append!{T<:CHARS}(block::Block{T}, ind, dest::NullableVector, offset, len, other)
    values = dest.values
    isnull = dest.isnull
    ccall(:jl_array_grow_end, Void, (Any, UInt), values, len)
    ccall(:jl_array_grow_end, Void, (Any, UInt), isnull, len)
    block2 = Block(block)
    cur = block2.ptr
    elsize = block2.elsize
    for i = 1:len
        @inbounds values[i+offset] = Data.PointerString(cur, bytes2codeunits(T,ind[i]))
        @inbounds isnull[i+offset] = ind[i] == ODBC.API.SQL_NULL_DATA
        cur += elsize
    end
    push!(other,block2)
    return nothing
end
