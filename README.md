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

On the other hand, if you see improvements, now is the time to raise an issue.

## Installation

You will need the C library [cifapi](https://github.org/comcifs/cif_api) installed 
in a standard place on your system.

## Getting started

Type ``NativeCif`` is like a ``Dict{String,NativeBlock}``. A
``NativeBlock`` works like a ``Dict{String,Any}``.  All returned
values are Arrays, **even if the data name appears as a key-value
pair**. Primitive values are always Strings, unless a DDLm dictionary
has been assigned to the ``NativeBlock``, in which case types are
converted before return. In this case CIF2 Tables are julia ``Dict``
types, and CIF2 lists are julia ``Array`` types.

### Reading

To open a file, and read ``_cell.length_a`` from a block, returning a
one-element ``Array{String,1}``:

```julia

using CrystalInfoFramework

d = NativeCif("my_cif.cif")
b = d["only_block"]  #could also use first(d)
l = b["_cell.length_a"]
["5.3"]
```

To use dictionary type information, assign a dictionary to a block:

```julia
my_dict = Cifdic("cif_core.dic")
bd = assign_dictionary(b,my_dict)
l = b["_cell.length_a"]
5.3
```

``get_loop``, returns a DataFrame object that can be manipulated using the 
methods of that package, most obviously, ``eachrow`` to iterate over the
packets in a loop:

```julia
l = get_loop(b,"_atom_site.label")
for r in eachrow(l)
    println("$(r[Symbol("_atom_site.pos_x")])")
end
```

### Updating

Values are added in the same way as for a normal dictionary.  No value
type checking is performed even if a dictionary has been assigned.

```julia
b["_new_item"] = [1,2,3]
```

If the dataname belongs to a loop, following assignment of the value the
new dataname can be added to a previously-existing loop. The following
call adds ``_new_item`` to the loop containing ``_old_item``:

```julia
add_to_loop(b,"_old_item","_new_item")
```

The number of values assigned to ``_new_item`` must match the length of
the loop - this is checked.

### Writing

There is currently no support for output of ``NativeCif`` (or any other) types. 
Contributions welcome.

## Architecture

The C cifapi library is used for parsing into native Julia structures. Aan
earlier version visible in the git history used cifapi for all interactions,
but the limitation to one loop traversal at a time was too restrictive.

A datablock with a dictionary assigned is a separate type.

## Further information

Read the tests in the tests directory for typical usage examples.
