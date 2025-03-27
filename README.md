![Testing](https://github.com/jamesrhester/CrystalInfoFramework.jl/workflows/Run%20tests/badge.svg)
[![Coverage Status](https://coveralls.io/repos/github/jamesrhester/CrystalInfoFramework.jl/badge.svg?branch=master&service=github)](https://coveralls.io/github/jamesrhester/CrystalInfoFramework.jl?branch=master)
# CrystalInfoFramework.jl

Julia tools for working with the
[Crystallographic Information Framework](https://www.iucr.org/resources/cif), 
including reading data files in Crystallographic Information Format (CIF) 
versions 1 and 2 (this includes mmCIF files from the PDB). As CIF format is a 
significant subset of STAR format, files in STAR format are
likely to read in without problems. The tools also
understand dictionaries written in DDLm and DDL2, which can be used to return correct
types and find aliased datanames (note that this includes the PDB
mmCIF dictionaries).

## Installation

Once Julia is installed, it is sufficient to `add CrystalInfoFramework`
at the Pkg prompt (accessed by the `]` character in the REPL).

## Documentation

Detailed documentation is available 
[here](https://jamesrhester.github.io/CrystalInfoFramework.jl/).

## Getting started

Type ``Cif`` is like a ``Dict{String,Block}``. A
``Block`` works like a ``Dict{String,Array{Any,1}}``.  All returned
values are Arrays, **even if the data name appears as a key-value
pair in the file**. Primitive values are always `String`s. 
CIF2 Tables become julia ``Dict`` types, and CIF2 lists are julia 
``Array`` types.

Even in the presence of a dictionary, DDLm Set category values are
returned as 1-element Arrays. **This may change in the future**

### Reading

``Cif`` objects are created by calling the ``Cif`` constructor with a
file name.  A ``Cif`` can be created directly from a
``String`` in CIF format by calling ``cif_from_string``.

To open a file, and read ``_cell.length_a`` from block ``only_block``, 
returning a one-element ``Array{String,1}``:

```julia

julia> using CrystalInfoFramework

julia> nc = Cif("my_cif.cif")
...
julia> my_block = nc["only_block"]  #could also use first(nc).second
...
julia> l = my_block["_cell.length_a"]
1-element Array{Any,1}:
 "11.520(12)"
```

``get_loop`` returns a ``DataFrame`` object that can be manipulated using the 
methods of that package, most obviously, ``eachrow`` to iterate over the
packets in a loop:

```julia

julia> l = get_loop(my_block,"_atom_site.label")
...
julia> for r in eachrow(l)
    println("$(r[Symbol("_atom_site.fract_x")])")
end
```

### Updating

Values are added in the same way as for a normal dictionary.

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

## Dictionaries

CIF dictionaries are created by passing the dictionary file name to
``DDLm_Dictionary`` or ``DDL2_Dictionary`` constructors.

### Writing

Use ``show(io::IO,::MIME"text/cif",d)`` to produce
correctly-formatted dictionaries or data files.

## See Also

(Raise a PR if you'd like your software listed here).

* [``julia_cif_tools``](https://github.com/jamesrhester/julia_cif_tools): Small programs
making use of this project. Good source of examples.

* [[``ImgCIFHandler.jl``](https://github.com/jamesrhester/ImgCIFHandler.jl): Julia package
for reading imgCIF data files. Includes scripts to check imgCIF data files for
consistency.

* [``CrystalInfoContainers.jl``](https://github.com/jamesrhester/CrystalInfoContainers.jl):
Use CIF dictionary information to organise data from arbitrary sources into relational
environment.

* [``DrelTools.jl``](https://github.com/jamesrhester/DrelTools.jl): Interpret and execute
dREL expressions found in CIF dictionaries in the relational environment provided by
``CrystalInfoContainers.jl``.

## Architecture

The C cif_api library parsing callbacks are used
to construct a `Cif` object during file traversal. The Julia parser uses 
a pre-built parser generated by ``Lerche`` using a CIF
EBNF to produce a parse tree that is then transformed into a `Cif`
object.

## Further information

Read the tests in the tests directory for typical usage examples.

## Contributing

Contributions, suggestions, and bug reports are welcome! Please use
Github issues and pull requests to do this.
