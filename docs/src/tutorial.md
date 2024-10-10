# Guide

The CIF files used in these examples are provided in the `docs` directory.

## Reading a CIF file

To open CIF file `demo.cif`, and read `_cell.length_a` from block `saly2_all_aniso`:

```jldoctest nick1

using CrystalInfoFramework, DataFrames

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

Option `native=false` to `Cif` will use the `cif_api` C parser instead of the
Julia parser. The `cif_api` parser is faster and more memory-efficient for
scripting use, whereas the native parser is faster if compilation time is
less of a consideration (e.g. multiple files are being read in). The
`cif_api` parser is not currently available on Windows systems.

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
columns corresponding to the data names provided to `create_loop!` must 
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

CIF dictionaries can be used with any `DataSource`, providing
that the datasource recognises the data names defined in the dictionary.

A `DataSource` is any object returning an array of values when
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
assume that the `DataSource` values are either already of the correct
type, or are `String`s that can be directly parsed by the Julia
`parse` method.

#### Creating new DataSources

A file format can be used with CIF dictionaries if:

1. It returns an `Array` of values when provided with a data name defined in the dictionary
2. `Array`s returned for data names from the same CIF category have corresponding values at the same position in the array - that is, they line up correctly if presented as columns in a table.

At a minimum, the following methods should be defined for the `DataSource`: 
`getindex`, `haskey`.

If the above are true of your type, then it is sufficient to define
`DataSource(::MyType) = IsDataSource()` to make it available.

If a `DataSource` `mds` can instead be modelled as a collection of
`DataSource`s, `iterate_blocks` should also be defined to iterate over
the constituent `DataSource`s. `MultiDataSource(mds)` will then create
a `DataSource` where values returned for any data names defined in the
constituent blocks are automatically aligned. Such `MultiDataSource`
objects can be built to form hierarchies.

#### Types

A `TypedDataSource` consists of a `DataSource` and a CIF dictionary.

Values returned from a `TypedDataSource` are transformed to the appropriate
Julia type as specified by the dictionary *if* the underlying 
`DataSource` returns `String` values formatted in a way that Julia `parse`
can understand.  Otherwise, the `DataSource` is responsible
for returning the appropriate Julia type. Future improvements
may add user-defined transformations if that proves necesssary.

A `NamespacedTypedDataSource` includes data from multiple namespaces.
Correctly-typed data for a particular namespace can then be obtained from 
the object returned by `select_namespace(t::NamespacedTypedDataSource,nspace)`.

## Cif Categories from DataSources

A CIF category (a 'Relation' in the relational model) can be constructed
from a `DataSource`, a CIF dictionary, and the CIF name of the category:

```jldoctest nick1
as = LoopCategory("atom_site",my_block,my_dict)

# output

Category atom_site Length 10
10×7 DataFrame. Omitted printing of 2 columns
│ Row │ u_iso_or_equiv │ fract_x   │ fract_z   │ adp_type  │ occupancy │
│     │ Cif Value…?    │ Cif Val…? │ Cif Val…? │ Cif Val…? │ Cif Val…? │
├─────┼────────────────┼───────────┼───────────┼───────────┼───────────┤
│ 1   │ .035(3)        │ .5505(5)  │ .1605(11) │ Uani      │ 1.00000   │
│ 2   │ .033(3)        │ .4009(5)  │ .2290(11) │ Uani      │ 1.00000   │
│ 3   │ .043(4)        │ .2501(5)  │ .6014(13) │ Uani      │ 1.00000   │
│ 4   │ .029(4)        │ .4170(7)  │ .4954(15) │ Uani      │ 1.00000   │
│ 5   │ .031(5)        │ .3145(7)  │ .6425(16) │ Uani      │ 1.00000   │
│ 6   │ .040(5)        │ .2789(8)  │ .8378(17) │ Uani      │ 1.00000   │
│ 7   │ .045(6)        │ .3417(9)  │ .8859(18) │ Uani      │ 1.00000   │
│ 8   │ .045(6)        │ .4445(9)  │ .7425(18) │ Uani      │ 1.00000   │
│ 9   │ .038(5)        │ .4797(8)  │ .5487(17) │ Uani      │ 1.00000   │
│ 10  │ .029(4)        │ .4549(7)  │ .2873(16) │ Uani      │ 1.00000   │

```

where a category is either a `LoopCategory`, with one or more rows, or
a `SetCategory`, which is restricted to a single row. Alternatively,
a `TypedDataSource` can be used, in which case the dictionary used by
the `TypedDataSource` is also used for category construction.

```jldoctest nick1
as = LoopCategory("atom_site",bd)

# output

Category atom_site Length 10
10×7 DataFrame. Omitted printing of 2 columns
│ Row │ u_iso_or_equiv │ fract_x   │ fract_z   │ adp_type  │ occupancy │
│     │ Cif Value…?    │ Cif Val…? │ Cif Val…? │ Cif Val…? │ Cif Val…? │
├─────┼────────────────┼───────────┼───────────┼───────────┼───────────┤
│ 1   │ .035(3)        │ .5505(5)  │ .1605(11) │ Uani      │ 1.00000   │
│ 2   │ .033(3)        │ .4009(5)  │ .2290(11) │ Uani      │ 1.00000   │
│ 3   │ .043(4)        │ .2501(5)  │ .6014(13) │ Uani      │ 1.00000   │
│ 4   │ .029(4)        │ .4170(7)  │ .4954(15) │ Uani      │ 1.00000   │
│ 5   │ .031(5)        │ .3145(7)  │ .6425(16) │ Uani      │ 1.00000   │
│ 6   │ .040(5)        │ .2789(8)  │ .8378(17) │ Uani      │ 1.00000   │
│ 7   │ .045(6)        │ .3417(9)  │ .8859(18) │ Uani      │ 1.00000   │
│ 8   │ .045(6)        │ .4445(9)  │ .7425(18) │ Uani      │ 1.00000   │
│ 9   │ .038(5)        │ .4797(8)  │ .5487(17) │ Uani      │ 1.00000   │
│ 10  │ .029(4)        │ .4549(7)  │ .2873(16) │ Uani      │ 1.00000   │

```

`getindex` for CIF categories uses the indexing value as the *key value*
for looking up a row in the category:

```jldoctest nick1
one_row = as["o1"]
one_row.fract_x

# output

".5505(5)"

```

If a category key consists multiple data names, a `Dict{Symbol,V}` should
be provided as the indexing value, where `Symbol` is the `object_id` of
the particular data name forming part of the key and `V` is the type of
the values.

A category can be iterated over as usual, with the value of each dataname
for each row available as a property:

```jldoctest nick1
for one_row in as
    println("$(one_row.label) $(one_row.fract_x) $(one_row.fract_y) $(one_row.fract_z)")
end

# output

o1 .5505(5) .6374(5) .1605(11)
o2 .4009(5) .5162(5) .2290(11)
o3 .2501(5) .5707(5) .6014(13)
c1 .4170(7) .6930(8) .4954(15)
c2 .3145(7) .6704(8) .6425(16)
c3 .2789(8) .7488(8) .8378(17)
c4 .3417(9) .8529(8) .8859(18)
c5 .4445(9) .8778(9) .7425(18)
c6 .4797(8) .7975(8) .5487(17)
c7 .4549(7) .6092(7) .2873(16)

```

If you prefer the `DataFrame` tools for working with tables, `DataFrame(c::CifCategory)`
creates a `DataFrame`:

```jldoctest nick1
DataFrame(as)

# output

10×7 DataFrame. Omitted printing of 2 columns
│ Row │ u_iso_or_equiv │ fract_x   │ fract_z   │ adp_type  │ occupancy │
│     │ Cif Value…?    │ Cif Val…? │ Cif Val…? │ Cif Val…? │ Cif Val…? │
├─────┼────────────────┼───────────┼───────────┼───────────┼───────────┤
│ 1   │ .035(3)        │ .5505(5)  │ .1605(11) │ Uani      │ 1.00000   │
│ 2   │ .033(3)        │ .4009(5)  │ .2290(11) │ Uani      │ 1.00000   │
│ 3   │ .043(4)        │ .2501(5)  │ .6014(13) │ Uani      │ 1.00000   │
│ 4   │ .029(4)        │ .4170(7)  │ .4954(15) │ Uani      │ 1.00000   │
│ 5   │ .031(5)        │ .3145(7)  │ .6425(16) │ Uani      │ 1.00000   │
│ 6   │ .040(5)        │ .2789(8)  │ .8378(17) │ Uani      │ 1.00000   │
│ 7   │ .045(6)        │ .3417(9)  │ .8859(18) │ Uani      │ 1.00000   │
│ 8   │ .045(6)        │ .4445(9)  │ .7425(18) │ Uani      │ 1.00000   │
│ 9   │ .038(5)        │ .4797(8)  │ .5487(17) │ Uani      │ 1.00000   │
│ 10  │ .029(4)        │ .4549(7)  │ .2873(16) │ Uani      │ 1.00000   │

```
