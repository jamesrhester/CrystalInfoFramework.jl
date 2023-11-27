## *Data Source Types*
#
# A DataSource returns ordered arrays of values when
# supplied with a data name. It additionally returns the
# corresponding values of other data names when supplied
# with an index.  This correspondence is opportunistic,
# and does not need to be meaningful.  The default methods
# assume that identical indices correspond.
#
# Parallel types allow the datanames to be drawn from
# namespaces.
#
## **Exports**

export DataSource,MultiDataSource, TypedDataSource
export IsDataSource
export AbstractRelationalContainer, RelationalContainer,DDLmCategory, CatPacket
export NamespacedRC, CifCategory, LoopCategory

# We implement DataSources as traits to allow them to be
# grafted onto other file formats.

"""
A `DataSource`, when provided with a string referring to a data name
from a namespace known to the data source, returns an array of values
that are either `Native` (already Julia types) or `Text` (requiring
interpretation to create Julia types).
"""
abstract type DataSource end
struct IsDataSource <: DataSource end
struct IsNotDataSource <: DataSource end

DataSource(::Type) = IsNotDataSource()

abstract type NamespacedDataSource <: DataSource end

# **Combined data sources**
#
# Multiple data sources are also data sources. This trait can be applied to preexisting
# data storage formats, and then logic here will be used to handle creation of
# associations between data names in component data sources.
#
# The multi-data-source is conceived as a container holding data sources.
#
# Value associations within siblings are preserved. Therefore it is not
# possible in general to match indices in arrays in order to obtain
# corresponding values, as some siblings may have no values for a data
# name that has them in another sibling.
#
# Scenarios:
# 1. 3 siblings, empty parent, one sibling contains many singleton values
# -> all singleton values are associated with values in the remaining blocks
# 1. As above, siblings contain differing singleton values for a data name
# -> association will be with anything having the same number of values, and
# with values within each sibling block
# 1. As above, one sibling contains an association between data names, another
# has only one of the data names and so no association
# -> The parent retains the association in the sibling that has it
# 1. Siblings and a contentful parent: parent is just another data block

struct MultiDataSource{T} <: DataSource
    wrapped::T
    cache::Dict{String,Any}
end

MultiDataSource(x) = MultiDataSource(x,Dict{String,Any}())

# **Typed data source**
#

"""
    TypedDataSource(data,dictionary)

A `TypedDataSource` is a `DataSource` that returns items with the correct type
and aliases resolved, as specified in the associated CIF dictionary. The
dictionary also provides a namespace.
"""
struct TypedDataSource{T} <: NamespacedDataSource
    data::T
    dict::AbstractCifDictionary
end

# == Relations ==

# A Relation is an object in a RelationalContainer (see below). It
# corresponds to an object in a mathematical category, or a relation in
# the relational model. Objects must have an identifier function that
# provides an opaque label for an object. We also want to be able to
# iterate over all values of this identifier, and other relations will
# pass us values of this identifier. Iteration produces a Row object.

abstract type Relation end
abstract type Row end

#==

 A RelationalContainer models a system of interconnected tables
 conforming the relational model, with an eye on the functional
 representation and category theory.  Dictionaries are used to
 establish inter-category links and category keys. Any alias and type
 information is ignored. If this information is relevant, the data
 source must handle it (e.g. by using a TypedDataSource).

 Although it is expected that the dictionary for each namespace will
 be identical in both the `TypedDataSource` and the dictionary, they
 are separated here and they are allowed to be different.  Keys and
 values still refer to the items stored in the container itself.

 A collection of named tables

=#

#=

Interface for a relational container:

has_category(arc, cat_name, (namespace))

haskey(arc, key, (namespace))

get(arc, key, (namespace)) <= take account of single-row categories

get_corresponding(arc, row, cat, (nspace))
   Find the row in `cat` corresponding to `row`, based on data name
   links.

get_dictionary(arc, (nspace))
  Return a dictionary describing the contents of arc

available_catobj(arc)
  List all cat,objs in container as tuples.
=#

abstract type AbstractRelationalContainer <: NamespacedDataSource end

# Sample implementation
"""
Values in a `RelationalContainer` are accessed by name or symbol.
In both cases the name/symbol belongs to a particular namespace. When
accessed by symbol, parent-child relationships are recognised for
both key and non-key data names. So, for example, if category
`atom_site_aniso` is a child category of `atom_site`, then member
`u11` of `atom_site_aniso` can be accessed as `:atom_site_aniso, :u_11`,
`:atom_site, :u_11` and `"_atom_site_aniso.u_11"`.

Similarly, if the
key data name for both categories is `<cat name>.label`, then a
particular row in either category can be indicated using all four
forms: `:atom_site, :label`, `:atom_site_aniso, :label`, "_atom_site.label"
or "_atom_site_aniso.label". This latter behaviour arises because of
the equivalence of key data names.
"""
struct RelationalContainer{T} <: AbstractRelationalContainer
    data::T    #usually values are TypedDataSource
    dict::AbstractCifDictionary
    name_to_catobj::Dict{String, Tuple{Symbol, Symbol}}
    catobj_to_name::Dict{Tuple{Symbol, Symbol}, String}
    cache::Dict{String,String} #for storing implicit values
end

"""
A NamespacedRC is a relational container where items are accessed by a
thruple (namespace, category, object).
"""
struct NamespacedRC{T} <: AbstractRelationalContainer
    relcons::Dict{String, RelationalContainer{T}}
end
              
# == Cif Categories == #

"""
A CifCategory describes a relation using a dictionary
"""
abstract type CifCategory <: Relation end

# A CifCategory has a dictionary!
get_dictionary(c::CifCategory) = throw(error("Implement get_dictionary for $(typeof(c))"))

# **CatPackets**

# A `CatPacket` is a row in the category. We allow access to separate elements of
# the packet using the property notation.

struct CatPacket <: Row
    id::Int
    source_cat::CifCategory
end

# **DDLm Categories**

# DDLm classifies relations into Set categories,
# and Loop categories. A Loop category can have
# child Loop categories.

abstract type DDLmCategory <: CifCategory end

# ***Loop Category***
#
# A LoopCategory is a DDLmCategory, and can have
# child categories whose columns are available for joining
# with the parent category using the keys.

struct LoopCategory <: CifCategory
    name::Symbol
    namespace::String
    column_names::Array{Symbol,1}
    children::Array{CifCategory, 1}
    selector::Dict{Symbol, Any}  #only these keys
    container::AbstractRelationalContainer
end

DataSource(LoopCategory) = IsDataSource()

