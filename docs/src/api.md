# API Documentation

## CIF files

A `Cif` is a collection of `CifContainer`s indexed by a `String` label.

```@docs
Cif(s::AbstractPath;verbose=false,native=false,version=0)
Cif(s::AbstractString;verbose=false,version=0,source=p"")
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

## CIF dictionaries

### DDLm Dictionaries 
Dictionaries published by the International Union of Crystallography
use the DDLm attribute set.

```@docs
DDLm_Dictionary
DDLm_Dictionary(c::Cif;ignore_imports=false)
DDLm_Dictionary(a::AbstractPath;verbose=false,ignore_imports=false)
keys(d::DDLm_Dictionary)
getindex(d::DDLm_Dictionary,k)
delete!(d::DDLm_Dictionary,k::String)
get_dic_namespace(d::DDLm_Dictionary)
list_aliases(d::DDLm_Dictionary,name;include_self=false)
find_name(d::DDLm_Dictionary,name)
find_category(d::DDLm_Dictionary,dataname)
find_object(d::DDLm_Dictionary,dataname)
is_category(d::DDLm_Dictionary,name)
get_categories(d::DDLm_Dictionary)
get_keys_for_cat(d::DDLm_Dictionary,cat;aliases=false)
get_default(d::DDLm_Dictionary,s)
lookup_default(dict::DDLm_Dictionary,dataname::String,cp)
show(io::IO,::MIME"text/cif",ddlm_dic::DDLm_Dictionary)
```

### DDL2 Dictionaries

DDL2 dictionaries are published and maintained by the worldwide
Protein Data Bank (wwPDB).

```@docs
DDL2_Dictionary
DDL2_Dictionary(c::Cif)
DDL2_Dictionary(a::AbstractPath;verbose=false)
keys(d::DDL2_Dictionary)
getindex(d::DDL2_Dictionary,k)
get_categories(d::DDL2_Dictionary)
get_default(d::DDL2_Dictionary,dataname)
show(io::IO,::MIME"text/cif",ddl2_dic::DDL2_Dictionary)
```

### Data Sources

Data from arbitrary file formats can be used as long as they
return an array of values when provided with a string.

```@docs
DataSource
TypedDataSource
```
