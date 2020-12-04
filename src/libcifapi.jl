# **Working with libcifapi**

# CIFs are transferred into Julia using the CIFAPI streaming facilities.
# No interface functions are provided for accessing full CIFs.

import Base.Libc:FILE

keep_alive = Any[]   #to stop GC freeing memory

"""
This represents the opaque cifapi `cif_tp` type.
"""
mutable struct cif_tp
end

"""A pointer to a `cif_tp` type managed by C"""
mutable struct cif_tp_ptr
    handle::Ptr{cif_tp}
end

"""A finalizer for a C-allocated CIF object"""
cif_destroy!(x) =  begin
    ##q = time_ns()
    ##error_string = "$q: Finalizing CIF object $x"
    ##t = @task println(error_string)
    ##schedule(t)
    val = ccall((:cif_destroy,"libcif"),Cint,(Ptr{cif_tp},),x.handle)
    if val != 0
        error(error_codes[val])
    end
end

"""
`cif_handler_tp` holds pointers to functions to be called when
specific CIF structures are encountered during parsing.
"""
struct cif_handler_tp
    cif_start::Ptr{Nothing}
    cif_end::Ptr{Nothing}
    block_start::Ptr{Nothing}
    block_end::Ptr{Nothing}
    frame_start::Ptr{Nothing}
    frame_end::Ptr{Nothing}
    loop_start::Ptr{Nothing}
    loop_end::Ptr{Nothing}
    packet_start::Ptr{Nothing}
    packet_end::Ptr{Nothing}
    handle_item::Ptr{Nothing}
end

#
# **Data blocks
#

"""
An opaque type representing a CIF block
"""
mutable struct cif_container_tp   #cif_block_tp in libcif
end

"""
A pointer to a CIF block or save frame, set by libcif
"""
mutable struct cif_container_tp_ptr
    handle::Ptr{cif_container_tp}  # *cif_block_tp
end

"""
    get_block_code(b::cif_container_tp_ptr)

Return the block code of the referenced container as a string
"""
get_block_code(b::cif_container_tp_ptr) = begin
    s = Uchar(0)
    val = ccall((:cif_container_get_code,"libcif"),Cint,(cif_container_tp_ptr,Ptr{Cvoid}),b,Ref(s))
    if val != 0
        error(error_codes[val])
    end
    make_jl_string(s)
end

"""
    keys(c::cif_tp_ptr)

Return all data block names from the referenced CIF file
"""
Base.keys(c::cif_tp_ptr) = get_block_code.(values(c))

# **CIF values**

"""
The type of data value in a CIF file
"""
mutable struct cif_value_tp
end

"""
A pointer to a data value in a CIF file
"""
mutable struct cif_value_tp_ptr
    handle::Ptr{cif_value_tp}
end

# All values returned by libcifapi have a string representation.

Base.String(t::cif_value_tp_ptr) = begin
   #Get the textual representation
   s = Uchar(0)
   val = ccall((:cif_value_get_text,"libcif"),Cint,(Ptr{cif_value_tp},Ptr{Cvoid}),t.handle,Ref(s))
   if val != 0
       error(error_codes[val])
   end
   new_string = make_jl_string(s)
end

# Classify the type. For numbers and strings we leave alone, so that the string
# retrieval above can use the pointer.

"""
    get_syntactical_type(t::cif_value_tp_ptr)

Determine the syntactical type of the data value.
"""
get_syntactical_type(t::cif_value_tp_ptr) = begin
    val_type = ccall((:cif_value_kind,"libcif"),Cint,(Ptr{cif_value_tp},),t.handle)
    if val_type == 0 || val_type == 1 return typeof(t)
    elseif val_type == 2 cif_list
    elseif val_type == 3 cif_table
    elseif val_type == 4 return Nothing
    elseif val_type == 5 return Missing
    end
end
    
# **Loops**

mutable struct cif_loop_tp
end

mutable struct cif_loop_tp_ptr
    handle::Ptr{cif_loop_tp}
end

"""
    keys(l::Ptr{cif_loop_tp})

List the data names in C data structure `l` corresponding to a CIF loop
"""
Base.keys(l::Ptr{cif_loop_tp}) = begin
    ukeys = Uchar_list(0)
    val = ccall((:cif_loop_get_names,"libcif"),Cint,(Ptr{cif_loop_tp},Ptr{Cvoid}),l,Ref(ukeys))
    if val != 0
        error(error_codes[val])
    end
    # ukeys will actually be a **UInt16, that is, after return it will hold a pointer to an array of UInt16
    if ukeys.strings == C_NULL
        error("Unable to get key list address")
    end
    # Now count how many values we have
    n = 1
    b = unsafe_load(ukeys.strings,n)
    #println("Start of actual array: $(b.string)")
    while b.string!=C_NULL
        n = n + 1
        b = unsafe_load(ukeys.strings,n)
        #println("Ptr is $(b.string)")
    end
    n = n - 1
    #println("Number of keys: $n")
    # Load in the UChar string pointers
    ukey_list = Vector{Uchar}(undef,n)
    for j=1:n
        ukey_list[j]=unsafe_load(ukeys.strings,j)
    end
    # Now actually turn them into ordinary strings
    key_list = make_jl_string.(ukey_list)
    # println("Found loop values $key_list")
    return key_list
end
    
# Loop packets. Only used as a pointer type for the callbacks

struct cif_packet_tp
end

# **Lists and Tables**

# These routines copy lists and tables from C to Julia

cif_list(cv::cif_value_tp_ptr) = begin
    cif_type = ccall((:cif_value_kind,"libcif"),Cint,(Ptr{cif_value_tp},),cv.handle)
    if cif_type != 2
        error("$val is not a cif list value")
    end
    elctptr = Ref{Cint}(0)
    val = ccall((:cif_value_get_element_count,"libcif"),Cint,(Ptr{cif_value_tp},Ptr{Cint}),cv.handle,elctptr)
    if val != 0
        error(error_codes[val])
    end
    elct = elctptr[]
    so_far = Vector()
    for el_num in 1:elct
        new_element = cif_value_tp_ptr(0)
        val = ccall((:cif_value_get_element_at,"libcif"),Cint,(Ptr{cif_value_tp},Cint,Ptr{cif_value_tp_ptr}),cv.handle,el_num-1,Ref(new_element))
        if val != 0
            error(error_codes[val])
        end
        t = get_syntactical_type(new_element)
        if t == cif_value_tp_ptr
            push!(so_far,String(new_element))
        elseif t == cif_list
            push!(so_far,cif_list(new_element))
        elseif t == cif_table
            push!(so_far,cif_table(new_element))
        else push!(so_far,t())
        end
    end
    return so_far
end

cif_table(cv::cif_value_tp_ptr) = begin
    cif_type = ccall((:cif_value_kind,"libcif"),Cint,(Ptr{cif_value_tp},),cv.handle)
    if cif_type != 3
        error("$val is not a cif table value")
    end
    so_far = Dict{String,Any}()
    for el in keys(cv)
        new_val = cv[el]
        t = get_syntactical_type(new_val)
        if t == cif_value_tp_ptr
            so_far[el]=String(new_val)
        elseif t == cif_list
            so_far[el]=cif_list(new_val)
        elseif t == cif_table
            so_far[el]=cif_table(new_val)
        else so_far[el]=t()
        end
    end
    return so_far
end

# The pointer passed to us should point to a table

Base.keys(ct::cif_value_tp_ptr) = begin
    ukeys = Uchar_list(0)
    #q = time_ns()
    #println("$q: accessing keys for $(ct.handle.handle)")
    val = ccall((:cif_value_get_keys,"libcif"),Cint,(Ptr{cif_value_tp},Ptr{Cvoid}),ct.handle,Ref(ukeys))
    if val != 0
        error(error_codes[val])
    end
    # ukeys will actually be a **UInt16, that is, after return it will hold a pointer to an array of UInt16
    if ukeys.strings == C_NULL
        error("Unable to get key list address")
    end
    # Now count how many values we have
    n = 1
    b = unsafe_load(ukeys.strings,n)
    # println("Start of actual array: $(b.string)")
    while b.string!=C_NULL
        n = n + 1
        b = unsafe_load(ukeys.strings,n)
        #println("Ptr is $(b.string)")
    end
    n = n - 1
    #println("Number of keys: $n")
    # Load in the UChar string pointers
    ukey_list = Vector{Uchar}(undef,n)
    for j=1:n
        ukey_list[j]=unsafe_load(ukeys.strings,j)
    end
    # Now actually turn them into ordinary strings
    # This is not strictly necessary in the context of iteration
    # but will probably help in debugging and error messages
    key_list = make_jl_string.(ukey_list)
end

# Access a CIF data value through the C library

Base.getindex(ct::cif_value_tp_ptr,key::AbstractString) = begin
    ukey = transcode(UInt16,key)
    append!(ukey,0)
    new_element = cif_value_tp_ptr(0)
    val = ccall((:cif_value_get_item_by_key,"libcif"),Cint,(Ptr{cif_value_tp},Ptr{UInt16},Ptr{cif_value_tp_ptr}),
        ct.handle,ukey,Ref(new_element))
    if val == 73
        throw(KeyError(key))
        end
    if val != 0
        error(error_codes[val])
    end
    return new_element
end

"""
The type of external Unicode strings from libicu
"""
mutable struct Uchar
    string::Ptr{UInt16}
end

"""
A list of Unicode strings
"""
mutable struct Uchar_list
    strings::Ptr{Uchar}
end

# **Utility routines**

"""
Obtain the length of a C null-terminated array `s`.
"""
get_c_length(s::Ptr,max=-1) = begin
    # Now loop over the values we have
    n = 1
    b = unsafe_load(s,n)
    while b!=0 && (max == -1 || (max != -1 && n < max))
        n = n + 1
        b = unsafe_load(s,n)
        #println("Char is $b")
    end
    n = n - 1
    #println("Length of string: $n")
    return n
end

# TODO: if this is used to make keys for a CIF table,
# we segfault if "own" is true. Why is that, and can
# we fix it

"""
Turn an ICU string into a Jula string
"""
make_jl_string(s::Uchar) = begin
    n = get_c_length(s.string,-1)  # short for testing
    icu_string = unsafe_wrap(Array{UInt16,1},s.string,n,own=false)
    block_code = transcode(String,icu_string)
end

