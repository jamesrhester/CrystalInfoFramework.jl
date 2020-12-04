# Test Data containers

using CrystalInfoFramework.DataContainer
using Test

# Test a plain CIF as data source

const cif_test_file = "nick1.cif"
const multi_block_test_file = "cif_img_1.7.11.dic"
const core_dic = "cif_core.dic"

prepare_files() = begin
    c = Cif(cif_test_file)
    b = first(c).second
end

prepare_blocks() = begin
    c = MultiDataSource(Cif(multi_block_test_file))
end

prepare_sources() = begin
    cdic = DDLm_Dictionary(core_dic)
    data = prepare_files()
    return (cdic,data)
end

@testset "Test simple dict as DataSource" begin
    testdic = Dict("a"=>[1,2,3],"b"=>[4,5,6],"c"=>[0],"d"=>[11,12])
    @test get_assoc_index(testdic,"b",3,"a") == 3
    @test get_all_associated_indices(testdic,"b","a") == [1,2,3]
    @test get_all_associated_indices(testdic,"b","c") == [1,1,1]
    @test get_assoc_value(testdic,"b",3,"a") == 3
    @test collect(get_all_associated_values(testdic,"b","a")) == [1,2,3]
    @test collect(get_all_associated_values(testdic,"b","c")) == [0,0,0]
end

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
        q = collect(get_all_associated_values(b,"_atom_type.number_in_cell","_atom_type.symbol"))
        println("Test 3: $q")
        q == ["O","C","H"]
    end

    # And if its a constant...
    @test begin
        b = prepare_files()
        q = collect(get_all_associated_values(b,"_atom_type_scat.source","_chemical_formula.sum"))
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

    @test begin
        b = prepare_blocks()
        ai = get_all_associated_indices(b,"_item.category_id","_item_type.code")
        ac = b["_item.category_id"]
        length(ai) == length(ac)
    end
    
    @test begin            #same save frame, no loop
        b = prepare_blocks()
        #r = get_assoc_value(b,"_item.category_id",4,"_item_type.code")
        # now we have to check!
        mb = first(b.wrapped).second
        s = get_assoc_value(b,"_item.category_id",4,"_item.name")
        println("Testing definition $s")
        defblock = mb.save_frames[s]
        ai = get_all_associated_indices(b,"_item.category_id","_item_type.code")
        an = get_all_associated_indices(b,"_item.category_id","_item.name")
        ac = b["_item.category_id"]
        at = b["_item_type.code"]
        names = b["_item.name"]
        println("$(at[ai[4]])")
        println("$(names[an[4]])")
        println("$(defblock)")
        at[ai[4]] == defblock["_item_type.code"][1] 
    end
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
    q = get_all_associated_indices(t,"_atom_site.fract_x","_atom_site.label")
    @test length(q) == length(t["_atom_site.fract_x"])
    q = get_all_associated_indices(t,"_atom_site_fract_x","_atom_site_label")
    @test length(q) == length(t["_atom_site_fract_x"]) #aliases
end

@testset "Test construction of a CifCategory" begin
    cdic,data = prepare_sources()
    atom_cat = LoopCategory("atom_site",data,cdic)
    @test get_key_datanames(atom_cat) == [:label]
    # Test getting a particular value
    mypacket = CatPacket(3,atom_cat)
    @test get_value(mypacket,:fract_x) == ".2501(5)"
    # Test relation interface
    @test get_value(atom_cat,Dict(:label=>"o2"),:fract_z) == ".2290(11)"
    # Test missing data
    empty_cat = LoopCategory("diffrn_orient_refln",data,cdic)
    # Test set category
    set_cat = SetCategory("cell",data,cdic)
    @test set_cat[:volume][] == "635.3(11)"
    # Test getting a key value
    @test atom_cat["o2"].fract_z == ".2290(11)"
end

@testset "Test child categories" begin
    cdic,data = prepare_sources()
    atom_cat = LoopCategory("atom_site",data,cdic)
    @test get_value(atom_cat,Dict(:label=>"o2"),:u_11) == ".029(3)"
end

@testset "Test behaviour of plain CatPackets" begin
    cdic,data  = prepare_sources()
    atom_cat = LoopCategory("atom_site",data,cdic)
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
    @test length(get_category(my_rc,"atom_type")[:atomic_mass]) == 3
    # sets
    @test get_category(my_rc,"cell")[:volume][] == 635.3
end

include("namespaces.jl")
