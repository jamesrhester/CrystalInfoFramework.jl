# Test execution of dREL code
using Test
using JuliaCif

setup() = begin
    p = cifdic("/home/jrh/COMCIFS/cif_core/cif_core.dic")
    define_dict_funcs(p)
    n = NativeCif(joinpath(@__DIR__,"nick1.cif"))
    b = n["saly2_all_aniso"]
    c = assign_dictionary(b,p)
    return dynamic_block(c)
end

const db = setup()

@testset "Test dictionary-defined functions" begin
    # Test that our functions are available
    d = get_dictionary(db)
    println("$(keys(d.func_defs))")
    @test get_func(d,"SymKey")("2_555",db) == 2
end

@testset "Test single-step derivation" begin
    s = derive(db,"_cell.atomic_mass")
    @test s[1] == 552.488
    println("$(code_typed(get_func(get_dictionary(db),"_cell.atomic_mass"),(dynamic_block,CatPacket)))")
    true
end

@testset "Test multi-step derivation" begin
    t = derive(db,"_cell.orthogonal_matrix")
    @test isapprox(t[1] , [11.5188 0 0; 0.0 11.21 0.0 ; -.167499 0.0 4.92], atol=0.01)
end

@testset "Test matrix multiplication" begin
    t = derive(db,"_cell.metric_tensor")
    @test isapprox(t[1], [132.71 0.0 -0.824094; 0.0 125.664 0.0; -0.824094 0.0 24.2064], atol = 0.01)
end

@testset "Test density" begin
    t = @time derive(db,"_exptl_crystal.density_diffrn")
    @test isapprox(t[1], db["_exptl_crystal.density_diffrn"][1],atol = 0.001)
    @time derive(db,"_exptl_crystal.density_diffrn")
end

@testset "Test tensor beta" begin
    t = @time derive(db,"_atom_site.tensor_beta")
    println("$t")
    println("$(code_typed(get_func(get_dictionary(db),"_atom_site.tensor_beta"),(dynamic_block,CatPacket)))")
    true
end
