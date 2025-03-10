# Tests of save frames
    
    @testset "Accessing save frames" begin
        b = prepare_block("has_save_frames.cif","has_save")
        fl = get_frames(b)
        fn = collect(keys(fl))
        @test length(fn) == 1
        @test fn[1] == "nested"
        @test haskey(fl,"Nested")   #should be detected
        @test haskey(fl["neSted"],"_nesting_level")
    end
