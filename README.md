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

## Warning: pre-1.0 release

Types, method names, and method signatures may change in later versions.

If you see ways to improve the naming or architecture, 
now is the time to raise an issue.

## Installation

Once Julia is installed, it is sufficient to `add CrystalInfoFramework`
at the Pkg prompt (accessed by the `]` character in the REPL).

## Documentation

Detailed documentation is becoming progressively available 
[here](https://jamesrhester.github.io/CrystalInfoFramework.jl/dev).

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

``Cif`` objects are created by calling the ``Cif`` constructor with a file
name. File names should be provided as ``FilePaths`` paths. These can be
produced from strings be prepending the letter ``p`` once ``FilePaths`` is
added. If a ``String`` is provided to the ``Cif`` constructor it will be
interpreted as the contents of a CIF file. The optional argument `native`
switches between the [C cif_api parser](https://github.com/COMCIFS/cif_api)
(`native=false`, not currently available for
Windows) and a native Julia parser (`native=true`, the default).

To open a file, and read ``_cell.length_a`` from block ``only_block``, 
returning a one-element ``Array{String,1}``:

```julia

julia> using CrystalInfoFramework, FilePaths

julia> nc = Cif(p"my_cif.cif")
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

## Dictionaries and DataSources

CIF dictionaries are created by passing the dictionary file name to
``DDLm_Dictionary`` or ``DDL2_Dictionary``. Either a ``FilePath`` or
``String`` may be used to specify the file location.

## DataSources

A ``DataSource`` is any data source returning an array of values when
supplied with a string.  A CIF ``Block`` conforms to this specification.
`` are defined in submodule ``CrystalInfoFramework.DataContainer``.

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

### Writing

Use ``show(io::IO,::MIME"text/cif",d)`` to produce
correctly-formatted dictionaries or data files.

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
