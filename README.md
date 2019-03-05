# CrystalInfoFramework.jl

Julia tools for working with the
[Crystallographic Information Framework](https://www.iucr.org/resources/cif), 
including reading data files in Crystallographic Information Format (CIF) 
versions 1 and 2 (this includes mmCIF files from the PDB). The tools also
understand dictionaries written in DDLm, which can be used to return correct
types and find aliased datanames (note that this is not available for mmCIF
as the PDB uses DDL2 dictionaries).

## Warning: early release

While usable for the bulk of typical tasks, this package is still in
an early version. Type and method names may change in later versions.
Various debugging messages are printed, some types lack informative
display.  Documentation strings are patchy.

On the other hand, if you see ways to improve the naming or architecture, 
now is the time to raise an issue.

## Installation

Apart from installing Julia, you will need the C library
[cifapi](https://github.org/comcifs/cif_api) installed in a standard
place on your system.

## Getting started

Type ``NativeCif`` is like a ``Dict{String,NativeBlock}``. A
``NativeBlock`` works like a ``Dict{String,Any}``.  All returned
values are Arrays, **even if the data name appears as a key-value
pair in the file**. Primitive values are always Strings, unless a DDLm dictionary
has been assigned to the ``NativeBlock``, in which case types are
converted before return. In this case CIF2 Tables become julia ``Dict``
types, and CIF2 lists are julia ``Array`` types.

Even in the presence of a dictionary, DDLm Set category values are
returned as 1-element Arrays. **This may change in the future**

### Reading

To open a file, and read ``_cell.length_a`` from block ``only_block``, 
returning a one-element ``Array{String,1}``:

```julia

julia> using CrystalInfoFramework

julia> nc = NativeCif("my_cif.cif")
...
julia> my_block = nc["only_block"]  #could also use first(d).second
...
julia> l = my_block["_cell.length_a"]
1-element Array{Any,1}:
 "11.520(12)"
```

To use dictionary type information, assign a dictionary to a block.

```julia
julia> my_dict = Cifdic("cif_core.dic")
...
julia> bd = assign_dictionary(my_block,my_dict)
julia> l = bd["_cell.length_a"]
1-element Array{Float64,1}:
 11.52
julia> l = bd["_cell_length_a"] #understand aliases
1-element Array{Float64,1}:
 11.52
```

``get_loop``, returns a DataFrame object that can be manipulated using the 
methods of that package, most obviously, ``eachrow`` to iterate over the
packets in a loop:

```julia

julia> l = get_loop(my_block,"_atom_site.label")
...
julia> for r in eachrow(l)
    println("$(r[Symbol("_atom_site.fract_x")])")
end
```

If a dictionary has been assigned, columns are labelled by their
``object_id``, not the full name:

```julia
julia> l = get_loop(bd,"_atom_site.label")
...
julia> for r in eachrow(l)
       println("$(r[Symbol("fract_x")])")
       end
0.5505
0.4009
0.2501
0.417
...
```

### Updating

Values are added in the same way as for a normal dictionary.  No value
type checking is performed even if a dictionary has been assigned.

```julia
my_block["_new_item"] = [1,2,3]
```

If the dataname belongs to a loop, following assignment of the value the
new dataname can be added to a previously-existing loop. The following
call adds ``_new_item`` to the loop containing ``_old_item``:

```julia
add_to_loop(my_block,"_old_item","_new_item")
```

The number of values in the array assigned to ``_new_item`` must match
the length of the loop - this is checked.

### Writing

There is currently no support for output of ``NativeCif`` (or any other) types. 
Contributions welcome.

## Architecture

The C cifapi library is used for parsing into native Julia structures. An
earlier version visible in the git history used cifapi for all interactions,
but the limitation to one loop traversal at a time was too restrictive.

A datablock with a dictionary assigned is a separate type.

## Further information

Read the tests in the tests directory for typical usage examples.
