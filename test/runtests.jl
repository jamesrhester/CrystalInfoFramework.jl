# Test Data containers

using DataContainer
using CrystalInfoFramework
using Test

# Test a plain CIF as data source

const cif_test_file = "nick1.cif"
const multi_block_test_file = "cif_img_1.7.11.dic"
const core_dic = "cif_core.dic"

prepare_files() = begin
    c = NativeCif(cif_test_file)
    b = first(c).second
end

prepare_blocks() = begin
    c = MultiDataSource(NativeCif(multi_block_test_file))
end

prepare_sources() = begin
    cdic = Cifdic(core_dic)
    data = prepare_files()
    return (cdic,data)
end

#==
@testset "Test CIF block as DataSource" begin

    # Within loop
    @test begin
        b = prepare_files()
        q = get_assoc_value(b,"_atom_type.atomic_mass",2,"_atom_type.symbol")
        println("Test 1: q is $q")
        q == "C"
    end

    # With constant value
    @test begin
        b = prepare_files()
        get_assoc_value(b,"_atom_type_scat.dispersion_imag",3,"_cell.volume") == "635.3(11)"
    end

    # Get all values
    @test begin
        b = prepare_files()
        q = get_all_associated_values(b,"_atom_type.number_in_cell","_atom_type.symbol")
        println("Test 3: $q")
        q == ["O","C","H"]
    end

    # And if its a constant...
    @test begin
        b = prepare_files()
        q = get_all_associated_values(b,"_atom_type_scat.source","_chemical_formula.sum")
        q == fill("C7 H6 O3",3)
    end
    
end


@testset "Test multi data block as DataSource" begin
    @test begin            #enclosing scope
        b = prepare_blocks()
        r = get_assoc_value(b,"_item_type.code",3,"_dictionary.datablock_id")
        println(r)
        r == "cif_img.dic"
    end

    @test begin            #same save frame loop
        b = prepare_blocks()
        r = get_assoc_value(b,"_item.mandatory_code",6,"_item.name")
        println(r)
        mb = first(b.wrapped).second
        defblock = mb.save_frames[r]
        defblock["_item.mandatory_code"][1] == b["_item.mandatory_code"][6]
    end

    @test begin            #same save frame, no loop
        b = prepare_blocks()
        r = get_assoc_value(b,"_item.category_id",4,"_item_type.code")
        # now we have to check!
        mb = first(b.wrapped).second
        s = get_assoc_value(b,"_item.category_id",4,"_item.name")
        println("Testing definition $s")
        defblock = mb.save_frames[s]
        defblock["_item_type.code"][1] == r
    end
end


@testset "Test auxiliary functions" begin
    cdic,data = prepare_sources()
    g = generate_keys(data,cdic,["_atom_site.label"],["_atom_site.fract_x"])
    println("keys are $g")
    @test ("c3",) in g

    i = generate_index(data,cdic,g,["_atom_site.label"],"_atom_site.fract_x")
    all_fracts = data["_atom_site.fract_x"]
    c3_index = indexin([("c3",)],g)[1]
    println("Index into data is $i")
    println("c3_index is $c3_index")
    @test all_fracts[i[c3_index]] == ".2789(8)"
end

@testset "Test TypedDataSources" begin
    cdic,data = prepare_sources()
    t = TypedDataSource(data,cdic)
    @test t["_cell.volume"][] == 635.3
    @test t["_cell_volume"][] == 635.3
    @test haskey(t,"_atom_type.symbol")
    @test haskey(t,"_atom_type_symbol")
    @test !haskey(t,"this_key_does_not_exist")
    q = get_assoc_value(t,"_atom_type.atomic_mass",2,"_atom_type.symbol")
    @test q == "C"
    q = get_assoc_value(t,"_atom_type.atomic_mass",2,"_cell_volume")
    @test q == 635.3
end
==#
@testset "Test construction of a CifCategory" begin
    cdic,data = prepare_sources()
    atom_cat = DDLmCategory("atom_site",data,cdic)
    @test get_key_datanames(atom_cat) == [:label]
    # Test getting a particular value
    mypacket = CatPacket(3,atom_cat)
    @test get_value(mypacket,"_atom_site.fract_x") == ".2789(8)"
    # Test relation interface
    @test get_value(atom_cat,Dict(:label=>"o2"),"_atom_site.fract_z") == ".2290(11)"
    # Test missing data
    empty_cat = DDLmCategory("diffrn_orient_refln",data,cdic)
    # Test set category
    set_cat = DDLmCategory("cell",data,cdic)
    @test set_cat[:volume][] == "635.3(11)"
    # Test getting a key value
    @test atom_cat["o2"].fract_z == ".2290(11)"
end

@testset "Test behaviour of plain CatPackets" begin
    cdic,data  = prepare_sources()
    atom_cat = DDLmCategory("atom_site",data,cdic)
    for one_pack in atom_cat
        @test !ismissing(one_pack.fract_x)
        if one_pack.label == "o2"
            @test one_pack.fract_z == ".2290(11)"
        end
    end
end

@testset "Test construction of RelationalContainers from Datasources and dictionaries" begin
    cdic,data = prepare_sources()
    ddata = TypedDataSource(data,cdic)
    my_rc = RelationalContainer(ddata,cdic)
    # loops
    @test length(my_rc["atom_type"][:atomic_mass]) == 3
    # sets
    @test my_rc["cell"][:volume][] == 635.3
end
