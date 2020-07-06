# Test function of namespaces
const second_cif = """#\\#CIF_2.0
data_second
 _cell.length_a  A
 _cell.length_b  B
loop_
 _atom_type.symbol
 _atom_type.atomic_mass
 Oxygen  15999
 Carbon  12011
 Hydrogen 1008
"""

const second_dic = """#\\#CIF_2.0

data_DODGY_DIC

_dictionary.title                       DODGY_DIC
_dictionary.class                       Instance
_dictionary.version                     3.0.13
_dictionary.date                        2020-03-16
_dictionary.ddl_conformance             3.14.0
_dictionary.namespace                   dodgy
_description.text                       
;
    The Dodgy dictionary provides completely worthless alternative
    definitions for a few common CIF data names
;

save_DODGY_CORE

_definition.id                          DODGY_CORE
_definition.scope                       Category
_definition.class                       Head
_definition.update                      2014-06-18
_description.text                       
;
     The DODGY_CORE group contains the definitions of data items that
     are common to all domains of crystallographic studies.
;
_name.category_id                       DODGY_DIC
_name.object_id                         DODGY_CORE

save_


save_CELL

_definition.id                          CELL
_definition.scope                       Category
_definition.class                       Set
_definition.update                      2012-11-22
_description.text                       
;
     The CATEGORY of data items used to describe the parameters of
     the crystal unit cell and their measurement.
;
_name.category_id                       DODGY_CORE
_name.object_id                         CELL

save_


save_cell.length_a
_definition.id                          '_cell.length_a'
_description.text                       
;
     The symbol for each cell axis.
;
    _type.purpose                Encode
    _type.source                 Recorded
    _type.container              Single
    _type.contents               Code

_name.category_id                       cell
_name.object_id                         length_a

save_

save_cell.length_b
_definition.id                          '_cell.length_b'
_description.text                       
;
     The symbol for each cell axis.
;
    _type.purpose                Encode
    _type.source                 Recorded
    _type.container              Single
    _type.contents               Code

_name.category_id                       cell
_name.object_id                         length_b

save_

save_ATOM_TYPE

_definition.id                          ATOM_TYPE
_definition.scope                       Category
_definition.class                       Loop
_definition.update                      2013-09-08
_description.text                       
;
     The CATEGORY of data items used to describe atomic type information
     used in crystallographic structure studies.
;
_name.category_id                       DODGY_CORE
_name.object_id                         ATOM_TYPE
loop_
  _category_key.name
         '_atom_type.symbol' 

save_

save_atom_type.symbol

_definition.id                          '_atom_type.symbol'
_description.text                       
;
     The identity of the atom specie(s) representing this atom type as
     a complete, capitalised word.
;
_name.category_id                       atom_type
_name.object_id                         symbol
_type.purpose                           Encode
_type.source                            Assigned
_type.container                         Single
_type.contents                          Text
save_

save_atom_type.atomic_mass

_definition.id                          '_atom_type.atomic_mass'
_description.text                       
;
     Molar mass of this atom type in milligrams
;
_name.category_id                       atom_type
_name.object_id                         atomic_mass
_type.purpose                           Number
_type.source                            Assigned
_type.container                         Single
_type.contents                          Real
_units.code                             milligrams

save_

"""

create_nspace_data() = begin
    cdic,data = prepare_sources()
    # create data with a different definition
    if !isfile("second.cif")
        s = open("second.cif","w")
        write(s,second_cif)
        close(s)
    end
    if !isfile("second.dic")
        s = open("second.dic","w")
        write(s,second_dic)
        close(s)
    end
    sdic = Cifdic("second.dic")
    sdata = first(NativeCif("second.cif")).second
    tdata = TypedDataSource(data,cdic)
    sdata = TypedDataSource(sdata,sdic)
    RelationalContainer([tdata,sdata])
end

@testset "Test namespace operations" begin
    nrc = create_nspace_data()
    @test has_category(nrc,"atom_type","CifCore")
    @test has_category(nrc,"atom_type","dodgy")
    @test !has_category(nrc,"atom_site","dodgy")
    @test get_data(nrc,"dodgy")["_atom_type.symbol"] == ["Oxygen","Carbon","Hydrogen"]
    @test get_data(nrc,"dodgy")["_cell.length_a"] == ["A"]
    @test nrc["dodgy‡_atom_type.symbol"] == ["Oxygen","Carbon","Hydrogen"]
    @test !haskey(nrc,"_atom_type.symbol")
    @test haskey(nrc,"CifCore‡_atom_type.symbol")
    c = get_category(nrc,"atom_site","CifCore")
    println("$c")
    @test haskey(c,"_atom_site.label")
    @test get_key_datanames(c) == [:label]
    @test c["o2"].fract_z == 0.2290
end

    
