# Types for working with arbitrary data
export DataSource,MultiDataSource, TypedDataSource
export IsDataSource
export CaselessString
export AbstractRelationalContainer,RelationalContainer,DDLmCategory, CatPacket
export CifCategory, LegacyCategory, SetCategory, LoopCategory


"""
## Data Source

Ultimately a DataSource holds values that are associated
with other values. This association is by location, not
intrinsic to the value itself.

A DataSource returns ordered arrays of values when
supplied with a data name. It additionally returns the
corresponding indices of other data names when supplied
with an index.  This correspondence is opportunistic,
and does not need to be meaningful.  The default methods
assume that identical indices correspond.

We implement DataSources as traits to allow them to be
grafted onto other file formats.

"""
abstract type DataSource end
struct IsDataSource <: DataSource end
struct IsNotDataSource <: DataSource end

DataSource(::Type) = IsNotDataSource()

"""
Multiple data sources are also data sources. This trait can be applied to preexisting
data storage formats, and then logic here will be used to handle creation of
associations between data names in component data sources.

The multi-data-source is conceived as a container holding data sources.

Value associations within siblings are preserved. Therefore it is not
possible in general to match indices in arrays in order to obtain
corresponding values, as some siblings may have no values for a data
name that has them in another sibling.

Scenarios:
1. 3 siblings, empty parent, one sibling contains many singleton values
-> all singleton values are associated with values in the remaining blocks
1. As above, siblings contain differing singleton values for a data name
-> association will be with anything having the same number of values, and
with values within each sibling block
1. As above, one sibling contains an association between data names, another
has only one of the data names and so no association
-> The parent retains the association in the sibling that has it
1. Siblings and a contentful parent: parent is just another data block
"""
struct MultiDataSource{T} <: DataSource
    wrapped::T
end

#==

A data source with an associated dictionary processes types and aliases.

==#

struct TypedDataSource <: DataSource
    data
    dict::abstract_cif_dictionary
end

# == Relations ==

""" 
A Relation is an object in a RelationalContainer (see below). It
corresponds to an object in a mathematical category, or a relation in
the relational model. Objects must have an identifier function that
provides an opaque label for an object. We also want to be able to
iterate over all values of this identifier, and other relations will
pass us values of this identifier. Iteration produces a Row object.
 """

abstract type Relation end
abstract type Row end

get_name(r::Relation) = throw(error("Not implemented"))

"""
Iterate over the identifier for the relation
"""
Base.iterate(r::Relation)::Row = throw(error("Not implemented"))

Base.iterate(r::Relation,s)::Row = throw(error("Not implemented"))

"""
Return all known mappings from a Relation
"""
get_mappings(r::Relation) = begin
    throw(error("Not implemented"))
end

"""
get_key_datanames returns a list of columns for the relation that, combined,
form the key. Column names must be symbols to allow rows to be selected using
other value types.
"""
get_key_datanames(r::Relation) = begin
    throw(error("Not implemented"))
end

get_category(r::Row) = throw(error("Not implemented"))

"""
Given an opaque row returned by iterator,
provide the value that it maps to for mapname
"""
get_value(row::Row,mapname) = begin
    throw(error("Not implemented"))
end

"""
A RelationalContainer models a system of interconnected tables conforming
the relational model, with an eye on the functional representation and
category theory.   Dictionaries are used to establish inter-category links
and category keys. Any alias and type information is ignored. If this
information is relevant, the data source must handle it (e.g. by using
a TypedDataSource).

Keys and values still refer to the items stored in the container itself.

"""
abstract type AbstractRelationalContainer <: DataSource end

struct RelationalContainer <: AbstractRelationalContainer
    rawdata::Dict{String,Any}     #namespace => data
    cifdics::Dict{String,abstract_cif_dictionary} #namespace=>dict
end

# == Cif Categories == #

"""
A CifCategory describes a relation using a dictionary
"""
abstract type CifCategory <: Relation end

# A CifCategory has a dictionary!
get_dictionary(c::CifCategory) = throw(error("Implement get_dictionary for $(typeof(c))"))

#=========

CatPackets

=========#

#==
A `CatPacket` is a row in the category. We allow access to separate elements of
the packet using the property notation.
==#

struct CatPacket <: Row
    id::Int
    source_cat::CifCategory
end

"""
A LegacyCategory is missing keys, so very little can be done
for it until the keys are generated somehow. We store the
data names that are available.
"""
struct LegacyCategory <: CifCategory
    name::String
    column_names::Array{Symbol,1}
    rawdata
    name_to_object::Dict{String,Symbol}
    object_to_name::Dict{Symbol,String}
    dictionary::DDLm_Dictionary
end

"""
DDLm classifies relations into Set categories,
and Loop categories.
"""
abstract type DDLmCategory <: CifCategory end
    
"""
A SetCategory has a single row and no keys, which means
that access via key values is impossible, but unambiguous
values are available
"""
struct SetCategory <: DDLmCategory
    name::String
    column_names::Array{Symbol,1}
    rawdata
    present::Array{Symbol,1}
    name_to_object::Dict{String,Symbol}
    object_to_name::Dict{Symbol,String}
    dictionary::DDLm_Dictionary
end

DataSource(::SetCategory) = IsDataSource()

"""
A LoopCategory is a DDLmCategory with keys
"""
struct LoopCategory <: CifCategory
    name::String
    column_names::Array{Symbol,1}
    keys::Array{Symbol,1}
    rawdata
    name_to_object::Dict{String,Symbol}
    object_to_name::Dict{Symbol,String}
    dictionary::abstract_cif_dictionary
end

    
DataSource(LoopCategory) = IsDataSource()

# == Caseless strings ==#

struct CaselessString <: AbstractString
    actual_string::String
end
