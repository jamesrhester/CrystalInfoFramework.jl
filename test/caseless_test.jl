# Test caseless strings
const testdic = Dict("a"=>1,"b"=>2,"c"=>3)
const testcsdic = Dict(zip(CaselessString.(["A","b","C"]),[1,2,3]))

@testset "Caseless string testing" begin
@test CaselessString("AbCdE") == SubstitutionString("abcDe")
@test SubstitutionString("aBcDe") == CaselessString("aBCDe")
@test CaselessString("AbCdE") == CaselessString("abCDe")
@test SubString(CaselessString("AbCDe"),1:3) == CaselessString("abc")
@test CaselessString("abc") == SubString(CaselessString("AbCDe"),1:3)
@test SubString(CaselessString("AbCDe"),1:3) == SubstitutionString("abc")
@test SubstitutionString("abc") == SubString(CaselessString("AbCDe"),1:3)
@test SubString(CaselessString("AbCDe"),1:3) == "ABC"
@test "ABC" == SubString(CaselessString("AbCDe"),1:3)

@test testdic[CaselessString("A")] == 1
@test testdic[SubString(CaselessString("AbCdE"),3,3)] == 3

    @test haskey(testcsdic,"B")
    
end
