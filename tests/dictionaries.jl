# Testing dictionary functionality

@testset "Testing dictionary access" begin
    @test begin
        t = cifdic(joinpath(@__DIR__,"ddl.dic"))
        true
    end
    @test begin
        t = cifdic(joinpath(@__DIR__,"ddl.dic"))
        String(t["_alias.deprecation_date"]["_type.source"]) == "Assigned"
    end
    
end
