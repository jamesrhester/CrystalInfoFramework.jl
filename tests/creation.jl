# Test CIF object creation and destruction
testdir = @__DIR__

@testset "Test simple CIF creation and destruction" begin

@test begin
    p = cif(joinpath(testdir,"simple_data.cif"))
    b = p["simple_data"]
    t = b["_numb_su"]
    true
end

@test begin
    p=cif()
    true    #if we succeed we are happy
end

@test begin
    p=cif(joinpath(testdir,"simple_data.cif"))
    true #if we succeed we are happy
end

@test begin
    p = cif(joinpath(testdir,"simple_data.cif"))
    b = p["simple_data"]
    bname = get_block_code(b)
    println("Block name is " * bname)
    bname == "simple_data"
end

@test begin
    p = cif(joinpath(testdir,"simple_loops.cif"))
    b = p["simple_loops"]
    l = get_loop(b,"_col2")
    true
end

end    #of testset

@testset "Loading native CIF" begin
    
    p = cif(joinpath(testdir,"simple_loops.cif"))
    @test begin
        q = load_cif(p)
        println("Full CIF is $q")
        true
    end
end
