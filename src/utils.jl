# compat
if !isdefined(Base, :unsafe_wrap)
    unsafe_string(ptr, len) = utf8(ptr, len)
    unsafe_wrap{A<:Array}(::Type{A}, ptr, len, own) = pointer_to_array(ptr, len, own)
end

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

"Create a new `Block` type from an existing `Block`, optionally only copying `n` bytes from `block`."
function Block{T}(block::Block{T},n::Integer=block.len)
    block2 = Block{T}(convert(Ptr{T},Libc.malloc(n)),n,block.elsize)
    ccall(:memcpy, Void, (Ptr{T}, Ptr{T}, Csize_t), block2.ptr, block.ptr, n)
    return block2
end

"Free the memory held by `block`. The `block` no longer points to valid memory."
free!(block::Block) = Libc.free(block.ptr)
"remove the .ptr from a Block to avoid unintentional referencing"
zero!(block::Block) = (block.ptr = 0; return nothing)

# used for getting messages back from ODBC driver manager; SQLDrivers, SQLError, etc.
Base.string(block::Block{UInt8},  len::Integer) = unsafe_string(block.ptr,len)
Base.string(block::Block{UInt16}, len::Integer) = Base.encode_to_utf8(UInt16, unsafe_wrap(Array, block.ptr, len, false), len)
Base.string(block::Block{UInt32}, len::Integer) = Base.encode_to_utf8(UInt32, unsafe_wrap(Array, block.ptr, len, false), len)

# translate a # of bytes and a code unit type (UInt8, UInt16, UInt32) and return the # of code units; returns 0 if field is null
bytes2codeunits(::Type{UInt8},  bytes::ODBC.API.SQLLEN) = ifelse(bytes == ODBC.API.SQL_NULL_DATA, convert(ODBC.API.SQLLEN,0), bytes)
bytes2codeunits(::Type{UInt16}, bytes::ODBC.API.SQLLEN) = ifelse(bytes == ODBC.API.SQL_NULL_DATA, convert(ODBC.API.SQLLEN,0), bytes >> 1)
bytes2codeunits(::Type{UInt32}, bytes::ODBC.API.SQLLEN) = ifelse(bytes == ODBC.API.SQL_NULL_DATA, convert(ODBC.API.SQLLEN,0), bytes >> 2)

const DECZERO = Dec64(0)

# conversion routines for "special" types where we can't just reinterpret the memory directly
cast{T}(::Type{T}, ptr, len) = WeakRefString(ptr, len)
cast(::Type{Vector{UInt8}}, ptr, len) = unsafe_wrap(Array, ptr, len, false)
cast(::Type{Dec64}, ptr, len) = len == 0 ? DECZERO : parse(Dec64, string(WeakRefString(ptr, len)))

# Used by streaming to CSV.Sink and SQLite.Sink; these operate on one field at a time (row/column)
getfield{T}(jltype,block::Block{T}, row, ind) = unsafe_load(block.ptr, row)
getfield{T<:CHARS}(jltype, block::Block{T}, row, ind) = cast(jltype, block.ptr + block.elsize * (row-1), ODBC.bytes2codeunits(T,ind))

"Take an `ind` indicator vector and return a `Vector{Bool}` with `false` entries for null/missing fields"
function booleanize!(ind::Vector{ODBC.API.SQLLEN},rows)
    new = Array(Bool, rows)
    @simd for i = 1:rows
        @inbounds new[i] = ind[i] == ODBC.API.SQL_NULL_DATA
    end
    return new
end
"Take an `ind` indicator vector and return a `Vector{Bool}` with `false` entries for null/missing fields"
function booleanize!(ind::Vector{ODBC.API.SQLLEN},new::Vector{Bool},offset,len)
    @simd for i = 1:len
        @inbounds new[i+offset] = ind[i] == ODBC.API.SQL_NULL_DATA
    end
    return new
end

"""create a NullableVector from a Block that has bitstype/immutable data;
   we're passing ownership of the memory to Julia and zeroing out the ptr in `block` (not freeing)"""
function NullableArrays.NullableArray{T}(jltype, block::Block{T}, ind, rows)
    a = NullableArray(unsafe_wrap(Array, block.ptr, rows, true), booleanize!(ind,rows))
    zero!(block)
    return a
end

"""
create a NullableVector from a Block that has container-type or Dec64 data.
We allocate a `rows`-length `values` array of the `jltype`, then run the necessary conversion method (`cast`)
on the `block` memory to get the appropriate `jltype` value.
We finish by "cleaning up" the `block` memory by:
  * Store the block as a Vector{UInt8} for blob and string types
  * Freeing the `block` memory for Dec64 since we're creating the separate Dec64 bitstype
"""
function NullableArrays.NullableArray{T<:CHARS,TT}(::Type{TT}, block::Block{T}, ind, rows)
    values = Array(TT, rows)
    cur = block.ptr
    elsize = block.elsize
    for row = 1:rows
        @inbounds values[row] = ODBC.cast(TT, cur, ODBC.bytes2codeunits(T,ind[row]))
        cur += elsize
    end
    if TT === Dec64
        free!(block)
        return NullableArray(values, booleanize!(ind,rows))
    else
        return NullableArray{TT,1}(values, booleanize!(ind,rows),
            unsafe_wrap(Array, convert(Ptr{UInt8}, block.ptr), block.len * sizeof(T), true))
    end
end

# copy!(rb.columns[col],rb.indcols[col],data[col],r,rows,other)
"fill a NullableVector by copying the data from a Block that has bitstype/immutable data"
function Base.copy!{T}(jltype, block::Block{T}, ind, dest::NullableVector, offset, len)
    ccall(:memcpy, Void, (Ptr{T}, Ptr{T}, Csize_t), pointer(dest.values) + offset * sizeof(T), block.ptr, len * sizeof(T))
    booleanize!(ind,dest.isnull,offset,len)
    return nothing
end

"fill a NullableVector by copying the data from a Block that has Dec64 data"
function Base.copy!{T<:CHARS}(::Type{Dec64}, block::Block{T}, ind, dest::NullableVector, offset, len)
    values = dest.values
    isnull = dest.isnull
    cur = block.ptr
    elsize = block.elsize
    for i = 1:len
        @inbounds values[i+offset] = cast(Dec64, cur, ODBC.bytes2codeunits(T,ind[i]))
        @inbounds isnull[i+offset] = ind[i] == ODBC.API.SQL_NULL_DATA
        cur += elsize
    end
    return nothing
end

"fill a NullableVector by copying the data from a Block that has container-type"
function Base.copy!{T<:CHARS}(jltype, block::Block{T}, ind, dest::NullableVector, offset, len)
    # basic strategy is:
      # grow dest.parent for the total # of bytes needed
      # copy block memory into parent
      # loop over block elsize and create WeakRefString(cur_ptr, ind[row])
    totalbytes = max(0, len == 1 ? ind[1] : len * block.elsize)
    last = endof(dest.parent)
    ccall(:jl_array_grow_end, Void, (Any, UInt), dest.parent, totalbytes)
    ccall(:memcpy, Void, (Ptr{UInt8}, Ptr{UInt8}, Csize_t), pointer(dest.parent) + last, block.ptr, totalbytes)
    values = dest.values
    isnull = dest.isnull
    cur = convert(Ptr{T}, pointer(dest.parent) + last)
    elsize = block.elsize
    for i = 1:len
        @inbounds values[i+offset] = ODBC.cast(jltype, cur, ODBC.bytes2codeunits(T,ind[i]))
        @inbounds isnull[i+offset] = ind[i] == ODBC.API.SQL_NULL_DATA
        cur += elsize
    end
    return nothing
end

"append to a NullableVector by copying the data from a Block that has bitstype/immutable data"
function Base.append!{T}(jltype, block::Block{T}, ind, dest::NullableVector, offset, len)
    ccall(:jl_array_grow_end, Void, (Any, UInt), dest.values, len)
    ccall(:memcpy, Void, (Ptr{T}, Ptr{T}, Csize_t), pointer(dest.values) + offset * sizeof(T), block.ptr, len * sizeof(T))
    ccall(:jl_array_grow_end, Void, (Any, UInt), dest.isnull, len)
    booleanize!(ind,dest.isnull,offset,len)
    return nothing
end

"append to a NullableVector by copying the data from a Block that has container-type data"
function Base.append!{T<:CHARS}(::Type{Dec64}, block::Block{T}, ind, dest::NullableVector, offset, len)
    values = dest.values
    isnull = dest.isnull
    ccall(:jl_array_grow_end, Void, (Any, UInt), values, len)
    ccall(:jl_array_grow_end, Void, (Any, UInt), isnull, len)
    cur = block.ptr
    elsize = block.elsize
    for i = 1:len
        @inbounds values[i+offset] = cast(Dec64, cur, ODBC.bytes2codeunits(T,ind[i]))
        @inbounds isnull[i+offset] = ind[i] == ODBC.API.SQL_NULL_DATA
        cur += elsize
    end
    return nothing
end

"append to a NullableVector by copying the data from a Block that has container-type data"
function Base.append!{T<:CHARS}(jltype, block::Block{T}, ind, dest::NullableVector, offset, len)
    values = dest.values
    isnull = dest.isnull
    ccall(:jl_array_grow_end, Void, (Any, UInt), values, len)
    ccall(:jl_array_grow_end, Void, (Any, UInt), isnull, len)
    totalbytes = max(0, len == 1 ? ind[1] : len * block.elsize)
    last = endof(dest.parent)
    ccall(:jl_array_grow_end, Void, (Any, UInt), dest.parent, totalbytes)
    ccall(:memcpy, Void, (Ptr{UInt8}, Ptr{UInt8}, Csize_t), pointer(dest.parent) + last, block.ptr, totalbytes)
    cur = convert(Ptr{T}, pointer(dest.parent) + last)
    elsize = block.elsize
    for i = 1:len
        @inbounds values[i+offset] = cast(jltype, cur, ODBC.bytes2codeunits(T,ind[i]))
        @inbounds isnull[i+offset] = ind[i] == ODBC.API.SQL_NULL_DATA
        cur += elsize
    end
    return nothing
end
