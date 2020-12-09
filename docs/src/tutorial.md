# Guide

The CIF files used in these examples are provided in the `docs` directory.

## Reading a CIF file

To open CIF file `demo.cif`, and read `_cell.length_a` from block `saly2_all_aniso`:

```jldoctest nick1

using CrystalInfoFramework

nc = Cif("demo.cif")
my_block = nc["saly2_all_aniso"]  #could also use first(nc).second
my_block["_cell.length_a"]

# output

1-element Array{Union{Missing, Nothing, Dict{String,T}, Array{T,1}, String} where T,1}:
 "11.520(12)"
```

Note that values are *always* returned as `Array` type, with the value for a key
value pair being a single-element array. The values in the arrays returned
are either `String`, `Missing` (CIF `?`), `Nothing` (CIF `.`) or compound types
`Dict` and `Array` which are only available for CIF2 syntax files.

### Loops

Individual columns are returned when the data name is requested, as above.

[`get_loop`](@ref) returns a `DataFrame` object that can be manipulated using the 
methods of that package, most obviously, `eachrow` to iterate over the
packets in a loop. To specify the required loop, simply provide any 
data name that appears in the loop.

```jldoctest nick1

l = get_loop(my_block,"_atom_site.label");

for r in eachrow(l)
    println("$(r[Symbol("_atom_site.fract_x")])")
end

# output

.5505(5)
.4009(5)
.2501(5)
.4170(7)
.3145(7)
.2789(8)
.3417(9)
.4445(9)
.4797(8)
.4549(7)
```

## Updating a CIF file

Single key-value pairs are added in the same way as for a normal dictionary. 

```julia
my_block["_new_item"] = "a fine item"
my_block["_number_item"] = 23
```

If the dataname belongs to a loop, a two-step process is required to add
the values. First the column of values for the new data name is added
as above, and then the new dataname can be added to a previously-existing 
loop. The following call adds `_new_loop_item` to the loop containing 
`_old_item`:

```julia
my_block["_new_loop_item"] = [1,2,3,4]
add_to_loop!(my_block,"_old_item","_new_loop_item")
```

The number of values in the array assigned to `_new_loop_item` must match
the length of the loop it is added to - this is checked.

A completely new loop can be created with [`create_loop!`](@ref).  The
columns corresponding to the data names provided to `create_loop` must 
have previously been added to the data block, just like for
[`add_to_loop!`](@ref).

## Writing CIFs

To write a CIF, open an IO stream and write the contents of the `Cif`
object as MIME type "text/cif":

```julia
t = open("newcif.cif","w")
show(t,MIME("text/cif"),mycif)
close(t)
```

Note that currently no checks are made for correct construction of
data names (e.g. leading underscore and characterset restrictions).
This will be checked in the future.

## Dictionaries and DataSources

### Dictionaries

CIF dictionaries are created by passing the dictionary file name to
[`DDLm_Dictionary`](@ref) or [`DDL2_Dictionary`](@ref) constructors. 
Note that DDL2
dictionaries are published by the Protein Data Bank (wwPDB) and DDLm
dictionaries are used by the IUCr.

```julia
d = DDLm_Dictionary("cif_core.dic")
```

### DataSources

CIF dictionaries can be used with any `DataSource`, providing that
that datasource recognises the data names defined in the dictionary.

A `DataSource` is any data source returning an array of values when
supplied with a string.  A CIF `Block` conforms to this
specification, as does a simple `Dict{String,Any}`.  `DataSource`s 
are defined in submodule `CrystalInfoFramework.DataContainer`.

A CIF dictionary can be used to obtain data with correct Julia type from
a `DataSource` that uses data names defined in the dictionary by 
creating a [`TypedDataSource`](@ref):

```jldoctest nick1
using CrystalInfoFramework.DataContainer
my_dict = DDLm_Dictionary("../test/cif_core.dic")
bd = TypedDataSource(my_block,my_dict)
bd["_cell.length_a"]

# output

1-element Array{Float64,1}:
 11.52

```

Note that the array elements are now `Float64` and that the standard
uncertainty has been removed. Future improvements may use
`Measurements.jl` to retain standard uncertainties.

Dictionaries also allow alternative names for a data name to be
recognised provided these are noted in the dictionary:

```jldoctest nick1

l = bd["_cell_length_a"] #no period in name

# output

1-element Array{Float64,1}:
 11.52

```

where `_cell_length_a` is the old form of the data name.

Currently transformations from `DataSource` values to Julia values
assume that the `DataSource` values are `String`s that can be
directly parsed by the Julia `parse` method. In the future this
will become a `DataSource`-specific operation to allow binary
formats to be handled.
