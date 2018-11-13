# Data access tests

# Simple value tests
@testset "Simple data values" begin
    b = prepare_block("simple_data.cif","simple_data")
    @test print(b["_numb_su"]) == "0.0625(2)"
    @test print(b["_unquoted_string"]) == "unquoted"
    @test print(b["_text_string"]) == "text"
    @test convert(Float64,b["_numb_su"]) ≈ 0.0625
    known_dnames =  Set(["_unknown_value",
"_na_value",
"_unquoted_string",
"_sq_string",      
"_dq_string",      
"_text_string",
"_numb_plain",    
"_numb_su",          
"_numb_tz",          
"_numb_quoted",      
"_query_quoted",     
"_dot_quoted"])       

    set_diff = setdiff(known_dnames, Set(keys(b)))
    println("Difference: $set_diff")
    @test length(set_diff) == 0
end

# Looped value tests
@testset "Looped values" begin
  b = prepare_block("simple_loops.cif","simple_loops")
  l = get_loop(b,"_col2")
  vals = []
  for p in l
      push!(vals,print(p["_col2"]))
  end
  @test Set(vals) == Set(["v1","v2","v3"])
end

# Test lists
@testset "List values" begin
    b = prepare_block("list_data.cif","list_data")
    l = b["_digit_list"]
    println("digit list is $l")
    r = collect(l)
    @test print.(r) == ["0","1","2","3","4","5","6","7","8","9"]
end

# Test tables
@testset "Table values" begin
b = prepare_block("table_data.cif","table_data")
l = b["_type_examples"]
@test convert(Float64,l["numb"])≈-123.4e+67
@test print(l["char"])=="char"
@test "unknown" in keys(l)
end

# Get the blocks
@testset "Block manipulations" begin
    t = cif(joinpath(@__DIR__,"simple_data.cif"))
    bl = values(t)
    @test get_block_code(bl[1]) == "simple_data"
end
