# Tests of save frames
b = prepare_block("has_save_frames.cif","has_save")
c = get_save_frame(b,"nested")
@test Number(c["_nesting_level"]) == 1

@testset "Working with lists of save frames" begin
    fl = get_all_frames(b)
    fn = get_block_code.(fl)
    @test length(fn) == 1
    @test fn[1] == "nested"
end
