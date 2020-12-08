# Guide

The CIF files used in these examples are provided in the `docs` directory.

## Reading a CIF file

To open a CIF file, and read ``_cell.length_a`` from block ``only_block``, 
returning a one-element ``Array{String,1}``:

```jldoctest nick1

julia> using CrystalInfoFramework;

julia> nc = Cif("demo.cif");

julia> my_block = nc["saly2_all_aniso"];  #could also use first(nc).second

julia> my_block["_cell.length_a"]

# output

1-element Array{Union{Missing, Nothing, Dict{String,T}, Array{T,1}, String} where T,1}:
  "11.520(12)"
```

``get_loop`` returns a ``DataFrame`` object that can be manipulated using the 
methods of that package, most obviously, ``eachrow`` to iterate over the
packets in a loop:

```jldoctest nick1

julia> l = get_loop(my_block,"_atom_site.label");

julia> for r in eachrow(l)
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
loop. The following call adds ``_new_loop_item`` to the loop containing 
``_old_item``:

```julia
my_block["_new_loop_item"] = [1,2,3,4]
add_to_loop(my_block,"_old_item","_new_loop_item")
```

The number of values in the array assigned to ``_new_loop_item`` must match
the length of the loop it is added to - this is checked.

## Writing CIFs

To write a syntactically-correct CIF, open an IO stream and write the
contents of the `Cif` object as MIME type "text/cif":

```julia
t = open("newcif.cif","w")
show(t,MIME("text/cif"),mycif)
close(t)
```

## Dictionaries and DataSources

CIF dictionaries are created by passing the dictionary file name to
``DDLm_Dictionary`` or ``DDL2_Dictionary`` constructors.

```julia
d = DDLm_Dictionary("cif_core.dic")
```

## DataSources

CIF dictionaries can be used with any ``DataSource``, providing that
that datasource recognises the data names defined in the dictionary.

A ``DataSource`` is any data source returning an array of values when
supplied with a string.  A CIF ``Block`` conforms to this
specification.  ``DataSource``s are defined in submodule
``CrystalInfoFramework.DataContainer``.

A CIF dictionary can be used to obtain data with correct Julia type from
a ``DataSource`` that uses data names defined in the dictionary by 
creating a ``TypedDataSource``:

```julia
julia> using CrystalInfoFramework.DataContainer
julia> my_dict = DDLm_Dictionary("cif_core.dic")
julia> bd = TypedDataSource(my_block,my_dict)
julia> l = bd["_cell.length_a"]
1-element Array{Float64,1}:
 11.52
julia> l = bd["_cell_length_a"] #understand aliases
1-element Array{Float64,1}:
 11.52
```
