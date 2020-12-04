# API Documentation

## CIF files

A `Cif` is a collection of `CifContainer`s indexed by a `String` label.

```@docs
Cif(s::AbstractString;verbose=false)
keys(c::Cif)
first(c::Cif)
length(c::Cif)
haskey(c::Cif,name)
getindex(c::Cif,n)
setindex!(c::Cif,v,n)
show(io::IO,::MIME"text/plain",c::Cif)
```

## CIF blocks

Concrete
types of `CifContainer`s are `Block` and `CifBlock`. Only the latter may
contain nested save frames.  `CifContainer`s act like `Dict{String,Array{CifValue,1}}` 
dictionaries indexed by data name.

```@docs
Block
CifBlock
keys(b::CifContainer)
haskey(b::CifContainer,s::String)
iterate(b::CifContainer)
getindex(b::CifContainer,s::String)
get(b::CifContainer,s::String,a)
getindex(b::CifContainer,s::Dict)
setindex!(b::CifContainer,v,s)
delete!(b::CifContainer,s)
```

## CIF values

Data names are associated with arrays of values of type `CifValue`.  Single-valued
data names are associated with arrays with a single element.

```@docs
CifValue
```

## Loops

CIF blocks contain key-value pairs and loops. The following methods give access to
these loops.

```@docs
get_loop
add_to_loop!
create_loop!
```

## Save frames

CIF data files do not contain save frames, however CIF dictionaries use them extensively. 
The contents of save frames are invisible to all
methods except `show`. They can be accessed using `get_frames`, which returns a `Cif` object.

```@docs
get_frames(f::CifBlock{V}) where V
```

