# Tests of save frames
for native = (true,false)
    b = prepare_block("has_save_frames.cif","has_save",native=native)
    
    @testset "Working with lists of save frames" begin
        fl = get_frames(b)
        fn = collect(keys(fl))
        @test length(fn) == 1
        @test fn[1] == "nested"
    end

end
