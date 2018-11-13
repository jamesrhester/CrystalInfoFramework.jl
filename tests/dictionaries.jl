# Testing dictionary functionality

@testset "Testing dictionary access and construction" begin
    @test begin
        t = cifdic(joinpath(@__DIR__,"ddl.dic"))
        true
    end
    @test begin
        t = cifdic(joinpath(@__DIR__,"ddl.dic"))
        String(t["_alias.deprecation_date"]["_type.source"]) == "Assigned"
    end
    @test begin
        t = cifdic(joinpath(@__DIR__,"ddl.dic"))
        String(get_by_cat_obj(t,("Type","Contents"))["_definition.class"]) == "Attribute"
    end
end

prepare_system() = begin
    t = cifdic(joinpath(@__DIR__,"cif_mag.dic"))
    u = cif(joinpath(@__DIR__,"AgCrS2.mcif")) #
    ud = assign_dictionary(u["AgCrS2_OG"],t)
end

@testset "Smart CIF blocks" begin
    ud = prepare_system()
    @test ud["_parent_space_group.IT_number"] == 160
    pl = get_loop(ud,"_atom_site_moment.crystalaxis_x")
    for one_pack in pl
        @test isapprox(one_pack["_atom_site_moment.crystalaxis_y"],2.66)
    end
    # now test some array items
    @test ud["_parent_propagation_vector.kxkykz"] == [-0.75, 0.75, -0.75]
end
