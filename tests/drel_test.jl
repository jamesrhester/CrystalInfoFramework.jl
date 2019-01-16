#Testing dREL runtime support
using JuliaCif

prepare_system() = begin
    t = cifdic(joinpath(@__DIR__,"cif_mag.dic"))
    u = NativeCif(joinpath(@__DIR__,"AgCrS2.mcif"))
    ud = assign_dictionary(u["AgCrS2_OG"],t)
end

@testset "Testing CategoryObject functionality" begin
    ud = prepare_system()
    c = CategoryObject(ud,"atom_site_moment")
    f = c[Dict("label"=>"Cr1_2")]
    @test (f.crystalaxis_y)[1] == 2.33
end

@testset "Testing expression processing" begin
    #ud = prepare_system()
    rawtext = :(a = [1,2,3,4]; b = a[0]; return b)
    newtext = ast_fix_indexing(rawtext,[])
    println("New text: $newtext")
    @test eval(newtext) == 1
    # So in the next test b becomes [1,3,5,7,9] and b[2] is 5 
    rawtext = :(a = [1,2,3,4,5,6,7,8,9]; c = 4; b = a[c-4:2:c+4]; return b[2])
    newtext = ast_fix_indexing(rawtext,[])
    println("New text: $newtext")
    @test eval(newtext) == 5
    rawtext = :(a = atom_site_moment::CategoryObject;a["label"] = "Hello";return true)
    newtext = ast_fix_indexing(rawtext,Symbol.(["__packet","atom_site_moment"]))
    println("New text: $newtext")
    @test true
    rawtext = :(f(x) = begin s = 1;for i = 1:5 if i == 3 q = 1 elseif i == 4 a = q end end; a end)
    newtext = fix_scope(rawtext)
    #println("New text: $newtext")
    eval(rawtext)
    # Make sure that Julia behaves as we expect
    @test_throws UndefVarError f(2) == 1
    eval(newtext)
    @test f(2) == 1
    #Now test that we properly process matrices
    rawtext = :(a.label = [[1,2,3],[4,5,6]]; return a)
    newtext = find_target(rawtext,"a","label";is_matrix=true)
    println("$newtext")
    @test eval(newtext) == [[1 2 3];[4 5 6]]
end
