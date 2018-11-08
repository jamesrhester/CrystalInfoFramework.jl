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
