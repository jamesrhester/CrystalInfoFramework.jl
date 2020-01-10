# Testing dictionary functionality

@testset "Testing dictionary access and construction" begin
    @test begin
        t = Cifdic(joinpath(@__DIR__,"ddl.dic"))
        true
    end
    @test begin
        t = Cifdic(joinpath(@__DIR__,"ddl.dic"))
        String(t["_alias.deprecation_date"]["_type.source"][1]) == "Assigned"
    end
    @test begin
        t = Cifdic(joinpath(@__DIR__,"ddl.dic"))
        String(get_by_cat_obj(t,("Type","Contents"))["_definition.class"][1]) == "Attribute"
    end
end

prepare_system() = begin
    t = Cifdic(joinpath(@__DIR__,"cif_mag.dic"))
    u = NativeCif(joinpath(@__DIR__,"AgCrS2.mcif")) #
    ud = assign_dictionary(u["AgCrS2_OG"],t)
end

@testset "Smart CIF blocks" begin
    ud = prepare_system()
    @test ud["_parent_space_group.IT_number"][1] == 160
    pl = get_loop(ud,"_atom_site_moment.crystalaxis_x")
    for one_pack in eachrow(pl)
        @test isapprox(one_pack[Symbol("crystalaxis_x")],0.0)
    end
    # now test some array items
    @test ud["_parent_propagation_vector.kxkykz"][1] == [-0.75, 0.75, -0.75]
    # test aliases
    @test "Cr1_1" in ud["_atom_site_moment_label"]
    @test "Cr1_1" in ud["_atom_site_moment.label"]
    # test key checks
    @test haskey(ud,"_atom_site_moment_crystalaxis_x")
    @test !haskey(ud,"_atom_site_moment_crystalaxis.q")
end

@testset "Importation" begin
    ud = prepare_system()
    @test String(ud.dictionary["_atom_site_rotation.label"]["_name.linked_item_id"][1]) == "_atom_site.label"
end
