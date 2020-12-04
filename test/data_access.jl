# Data access tests

# Simple value tests
@testset "Simple data values" begin
    b = prepare_block("simple_data.cif","simple_data")
    @test b["_numb_su"] == ["0.0625(2)"]
    @test b["_unquoted_string"] == ["unquoted"]
    @test b["_text_string"] == ["text"]
    known_dnames =  Set([    # "_unknown_value", # missing values are dropped
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
    for p in eachrow(l)
      push!(vals,String(p[:_col2]))
    end
    @test Set(vals) == Set(["v1","v2","v3"])
    # do it again as this has failed in the past
    m = get_loop(b,"_scalar_a")
    vals = []
    for p in eachrow(l)
        println("Do nothing")
        push!(vals,String(p[:_col2]))
    end
    @test Set(vals) == Set(["v1","v2","v3"])
    vals = []
    for q in eachrow(m)
        push!(vals,String(q[:_scalar_a]))
    end
    @test vals == ["a"]
    # test loop lookup
    p = b[Dict("_col2"=>"v3","_col3"=>"12.5(2)")]
    @test size(p,1) == 1
    @test p[!,"_col1"][1] == "3"
    # create a new loop
    create_loop!(b,["_col1","_single"])
    df = get_loop(b,"_col1")
    @test "_single" in names(df)
    @test !("_col2" in names(df))
    add_to_loop!(b,"_col1","_col2")
    df = get_loop(b,"_col3")
    @test !("_col2" in names(df))
end

# Test lists
@testset "List values" begin
    b = prepare_block("list_data.cif","list_data")
    l = b["_digit_list"]
    #println("digit list is $l")
    @test l[1] == ["0","1","2","3","4","5","6","7","8","9"]
end

# Test tables
@testset "Table values" begin
b = prepare_block("table_data.cif","table_data")
l = b["_type_examples"]
@test l[1]["numb"]=="-123.4e+67(5)"
@test l[1]["char"]=="char"
@test "unknown" in keys(l[1])
end

# Test both at once!
@testset "Lists and tables" begin
    b = prepare_block("table_list_data.cif","tl_data")
    l = b["_import.get"]
    @test ismissing(l[1][1]["block"])
    @test l[1][2]["c"]=="whatever"
    q = b["_list_in_table"]
    @test q[1]["q"][2] == "b"
end

# Test missing values are dropped completely

@testset "Missing values" begin
    b = prepare_block("missing_data.cif","miss_data")
    @test !haskey(b,"_col_missing")
    @test !haskey(b,"_scalar_b")
    @test !haskey(b,"_forget_it")
end
