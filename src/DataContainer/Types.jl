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
export AbstractRelationalContainer,RelationalContainer,DDLmCategory, CatPacket
export CifCategory, LegacyCategory, SetCategory, LoopCategory

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
end

# **Typed data source**
#

"""
    TypedDataSource(data,dictionary)

A `TypedDataSource` is a `DataSource` that returns items of with the correct type
and aliases resolved, as specified in the associated CIF dictionary.
"""
struct TypedDataSource <: DataSource
    data
    dict::AbstractCifDictionary
end

# ***With namespaces***

struct NamespacedTypedDataSource <: NamespacedDataSource
    data::Dict{String,TypedDataSource}
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

# A RelationalContainer models a system of interconnected tables conforming
# the relational model, with an eye on the functional representation and
# category theory.   Dictionaries are used to establish inter-category links
# and category keys. Any alias and type information is ignored. If this
# information is relevant, the data source must handle it (e.g. by using
# a TypedDataSource).
#
# Although it is expected that the dictionary for each namespace will
# be identical in both the `TypedDataSource` and the dictionary, they
# are separated here and they are allowed to be different.  Keys and
# values still refer to the items stored in the container itself.

abstract type AbstractRelationalContainer <: NamespacedDataSource end

struct RelationalContainer <: AbstractRelationalContainer
    data::Dict{String,Any}    #usually values are TypedDataSource
    dicts::Dict{String,AbstractCifDictionary}
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

# **Legacy Category**

# A LegacyCategory is missing keys, so very little can be done
# for it until the keys are generated somehow. We store the
# data names that are available.

struct LegacyCategory <: CifCategory
    name::String
    column_names::Array{Symbol,1}
    rawdata
    name_to_object::Dict{String,Symbol}
    object_to_name::Dict{Symbol,String}
    dictionary::AbstractCifDictionary
    namespace::String
end

# **DDLm Categories**

# DDLm classifies relations into Set categories,
# and Loop categories. A Loop category can have
# child Loop categories.

abstract type DDLmCategory <: CifCategory end
    
# ***Set Categories***
# A SetCategory has a single row and no keys, which means
# that access via key values is impossible, but unambiguous
# values are available. Child categories do not exist.

struct SetCategory <: DDLmCategory
    name::String
    column_names::Array{Symbol,1}
    rawdata
    present::Array{Symbol,1}
    name_to_object::Dict{String,Symbol}
    object_to_name::Dict{Symbol,String}
    dictionary::DDLm_Dictionary
    namespace::String
end

DataSource(::SetCategory) = IsDataSource()

# ***Loop Category***
#
# A LoopCategory is a DDLmCategory with keys, and can have
# child categories whose columns are available for joining
# with the parent category using the keys.

struct LoopCategory <: CifCategory
    name::String
    column_names::Array{Symbol,1}
    keys::Array{Symbol,1}
    rawdata
    name_to_object::Dict{String,Symbol}
    object_to_name::Dict{Symbol,String}
    child_categories::Array{LoopCategory,1}
    dictionary::AbstractCifDictionary
    namespace::String
end

DataSource(LoopCategory) = IsDataSource()

