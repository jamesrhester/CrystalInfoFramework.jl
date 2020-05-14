# Test Data containers

using DataContainer
using CrystalInfoFramework
using Test

# Test a plain CIF as data source

const cif_test_file = "nick1.cif"
const multi_block_test_file = "cif_img_1.7.11.dic"

prepare_files() = begin
    c = NativeCif(cif_test_file)
    b = first(c).second
end

prepare_blocks() = begin
    c = MultiDataSource(NativeCif(multi_block_test_file))
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
==#

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
        println( b["_item_default.value"])
        r = get_assoc_value(b,"_item.category_id",4,"_item_default.value")
        println(r)
        mb = first(b.wrapped).second
        defblock = mb.save_frames[r]
        defblock["_item.default_value"][1] == b["_item.category_id"][4]
    end
end
