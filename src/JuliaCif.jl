module JuliaCif
#= This module provides ways of interacting with a Crystallographic Information
 file using Julia. It currently wraps the C CIF API.
=#
include("cif_errors.jl")

import Base.Libc:FILE

"""
This represents the opaque cif_tp type.
"""
mutable struct cif_tp
end

"""A pointer to a cif_tp type managed by C"""
mutable struct cif_tp_ptr
    p::Ptr{cif_tp}
end

"""
A CIF object (may extend in the future)
"""
mutable struct cif
    handle::Ptr{cif_tp}
end

cif(x::cif_tp_ptr) = cif(x.p)

"""A finalizer for a C-allocated CIF object"""
cif_destroy!(x) =  begin
    val = ccall((:cif_destroy,"libcif"),Cint,(Ptr{cif_tp},),x.handle)
    #check val if necessary
end

"""Construct a new CIF object"""
cif()= begin
    dpp = cif_tp_ptr(0)   #Null pointer will be replaced by C call
    val=ccall((:cif_create,"libcif"),Cint,(Ref{cif_tp_ptr},),Ref(dpp))
    # Can error-check val if necessary
    r = cif(dpp)
    finalizer(cif_destroy!,r) #this will be called when finished
end

"""Parse input stream and return a CIF object"""
cif(f::IOStream) = begin
    cif()
    # get the underlying file descriptor, turn it into a FILE*
    # then call...
end

"""An opaque type representing the parse options object in libcif"""
struct cif_parse_options
end

"""A pointer to a parse options structure"""
mutable struct cpo_ptr
    handle::Ptr{cif_parse_options}
end

"""Free C resources for parse options"""
pos_destroy!(x::cpo_ptr) = begin
    ccall((:free,"libc"),Cvoid,(cpo_ptr,),x.handle)
end

"""Given a filename, parse and return a CIF object"""
cif(s::AbstractString)=begin
    # obtain an IOStream
    f = open(s,"r")
    fptr = Base.Libc.FILE(f)
    # create a parse options structure
    p_opts = cpo_ptr(0)
    val = ccall((:cif_parse_options_create,"libcif"),Cint,(Ref{cpo_ptr},),Ref(p_opts))
    dpp = cif_tp_ptr(0)   #value replaced by C library
    val=ccall((:cif_parse,"libcif"),Cint,(FILE,cpo_ptr,Ref{cif_tp_ptr}),fptr,p_opts,Ref(dpp))
    close(f)
    # can check val here
    if val != 0
        error(error_codes[val])
    end
    r = cif(dpp)
    finalizer(cif_destroy!,r)
end

#==
Routines for accessing parts of the CIF file
==#

#==
Data blocks
==#

"""An opaque type representing a CIF block"""
mutable struct cif_block_tp   #cif_block_tp in libcif
end

"""A pointer to a CIF block, set by libcif"""
mutable struct cif_block_tp_ptr
    handle::Ptr{cif_block_tp}  # *cif_block_tp
    # Need to register a finalizer as well
end

"""A simple wrapper for external use"""
struct cif_block
    handle::cif_block_tp_ptr   #*cif_block_libcif
end

cb_destroy!(cb::cif_block_tp_ptr) =  begin
    val = ccall((:cif_container_free,"libcif"),Cvoid,(Ptr{cif_block_tp},),cb.handle)
    if val != 0
        error("Failed to free cif block storage: $(error_codes[val])")
    end
end

get_block(c::cif,block_name::AbstractString) = begin
    cbt = cif_block_tp_ptr(0)
    bn_as_uchar = transcode(UInt16,block_name)
    val = ccall((:cif_get_block,"libcif"),Cint,(Ptr{cif_tp},Ptr{UInt16},Ptr{cif_block_tp_ptr}),
    c.handle,bn_as_uchar,Ref(cbt))
    # check val
    if val != 0
        error(error_codes[val])
    end
    finalizer(cb_destroy!,cbt)
    return cbt
end

# Libcif requires a pointer to a location where it can store a pointer to an array of block handles.
# After the call our pointer points to the start of an array of pointers
mutable struct block_list_ptr
    handle::Ptr{cif_block_tp_ptr}  #**cif_block_tp
end

"""Free the memory associated with each block"""
destroy_block_list!(p::Vector{cif_block_tp_ptr}) = begin
    foreach(cb_destroy!,p)
end

"""Get handles to all blocks in a data file"""
get_all_blocks(c::cif) = begin
    array_address = block_list_ptr(0)  #**cif_block_tp
    println("Array address before: $array_address")
    val = ccall((:cif_get_all_blocks,"libcif"),Cint,(Ptr{cif_tp},Ptr{block_list_ptr}),c.handle,Ref(array_address))
    if val!=0
        error(error_codes[val])
    end
    println("Array address after: $array_address")
    if array_address.handle == C_NULL
        error("Unable to get block array address")
    end
    # Now loop over the values we have
    n = 1
    b = unsafe_load(array_address.handle,n)
    println("Start of actual array: $(b.handle)")
    while b.handle!=C_NULL
        n = n + 1
        b = unsafe_load(array_address.handle,n)
        println("Ptr is $(b.handle)")
    end
    n = n - 1
    println("Number of blocks: $n")
    # Total length is n
    block_list = Vector{cif_block_tp_ptr}(undef,n)
    for j=1:n
        block_list[j]=unsafe_load(array_address.handle,j)
    end
    finalizer(destroy_block_list!,block_list)
    return block_list
end

"""The type external Unicode strings from libicu"""
mutable struct Uchar
    string::Ptr{UInt16}
end

"""Turning an ICU string into a Jula string"""
make_jl_string(s::Uchar) = begin
    n = get_c_length(s.string,-1)  # short for testing
    icu_string = unsafe_wrap(Array{UInt16,1},s.string,n,own=true)
    block_code = transcode(String,icu_string)
end

"""Obtain the name of a block"""
get_block_code(b::cif_block_tp_ptr) = begin
    s = Uchar(0)
    val = ccall((:cif_container_get_code,"libcif"),Cint,(Ptr{cif_block_tp},Ptr{Cvoid}),b.handle,Ref(s))
    if val != 0
        error(error_codes[val])
    end
    make_jl_string(s)
end

"""The general value type of a CIF file"""
struct cif_value_tp
end

mutable struct cif_value_tp_ptr
    handle::Ptr{cif_value_tp}
end

"""Return the value of an item"""
get_value(b::cif_block_tp_ptr,name::AbstractString) = begin
    new_val = cif_value_tp_ptr(0)
    uname = transcode(UInt16,name)
    val = ccall((:cif_container_get_value,"libcif"),Cint,(Ptr{cif_block_tp_ptr},Ptr{UInt16},Ptr{cif_value_tp_ptr}),
    b.handle,uname,Ref(new_val))
    if val != 0
        error(error_codes[val])
    end
    # Set the textual representation
    s = Uchar(0)
    val = ccall((:cif_value_get_text,"libcif"),Cint,(Ptr{cif_value_tp},Ptr{Cvoid}),new_val.handle,Ref(s))
    if val != 0
        error(error_codes[val])
    end
    new_string = make_jl_string(s)
end

"""Utility routine to get the length of a C null-terminated array"""
get_c_length(s::Ptr,max=-1) = begin
    # Now loop over the values we have
    n = 1
    b = unsafe_load(s,n)
    while b!=0 && (max == -1 || (max != -1 && n < max))
        n = n + 1
        b = unsafe_load(s,n)
        # println("Ptr is $b")
    end
    n = n - 1
    #println("Length of string: $n")
    return n
end

greet() = print("Hello World!")

end # module
