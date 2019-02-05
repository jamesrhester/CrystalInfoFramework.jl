# Test execution of dREL code
using Test
import JuliaCif
import JuliaCif.drel_exec

setup() = begin
    p = JuliaCif.cifdic("/home/jrh/COMCIFS/cif_core/cif_core.dic")
    JuliaCif.drel_exec.define_dict_funcs(p)
    n = JuliaCif.NativeCif(joinpath(@__DIR__,"nick1.cif"))
    b = n["saly2_all_aniso"]
    c = JuliaCif.assign_dictionary(b,p)
    return JuliaCif.drel_exec.dynamic_block(c)
end

const db = setup()

@testset "Test dictionary-defined functions" begin
# Test that our functions have been placed in the namespace
    @test JuliaCif.drel_exec.SymKey("2_555",db) == 2
end

@testset "Test single-step derivation" begin
    s = JuliaCif.drel_exec.derive(db,"_cell.atomic_mass")
    @test s[1] == 552.488
    println("$(code_typed(JuliaCif.drel_exec.func_lookup["_cell.atomic_mass"],(JuliaCif.drel_exec.dynamic_block,JuliaCif.CatPacket)))")
    true
end

@testset "Test multi-step derivation" begin
    t = JuliaCif.drel_exec.derive(db,"_cell.orthogonal_matrix")
    @test isapprox(t[1] , [11.5188 0 0; 0.0 11.21 0.0 ; -.167499 0.0 4.92], atol=0.01)
end

@testset "Test matrix multiplication" begin
    t = JuliaCif.drel_exec.derive(db,"_cell.metric_tensor")
    @test isapprox(t[1], [132.71 0.0 -0.824094; 0.0 125.664 0.0; -0.824094 0.0 24.2064], atol = 0.01)
end

@testset "Test density" begin
    t = @time JuliaCif.drel_exec.derive(db,"_exptl_crystal.density_diffrn")
    @test isapprox(t[1], db["_exptl_crystal.density_diffrn"][1],atol = 0.001)
    @time JuliaCif.drel_exec.derive(db,"_exptl_crystal.density_diffrn")
end

@testset "Test tensor beta" begin
    t = @time JuliaCif.drel_exec.derive(db,"_atom_site.tensor_beta")
    println("$t")
    println("$(code_typed(JuliaCif.drel_exec.func_lookup["_atom_site.tensor_beta"],(JuliaCif.drel_exec.dynamic_block,JuliaCif.CatPacket)))")
    true
end
