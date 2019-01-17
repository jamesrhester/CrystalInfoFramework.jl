#== This module defines an environment for executing dREL code
==#

module drel_exec

export dynamic_dict,dynamic_block

using JuliaCif

# Python setup calls

using PyCall


lark = PyNULL()
jl_transformer = PyNULL()

# Done this way to allow precompilation to work
__init__() = begin
    pushfirst!(PyVector(pyimport("sys")["path"]),@__DIR__)
    copy!(lark,pyimport("lark"))
    copy!(jl_transformer,pyimport("jl_transformer"))
end

using DataFrames

include("drel_runtime.jl")  #functions for runtime execution
include("drel_ast.jl") #functions for ast manipulation

# Configuration
const drel_grammar = joinpath(@__DIR__,"lark_grammar.ebnf")

# Create a parser for the dREL grammar

lark_grammar() = begin
    grammar_text = read(joinpath(@__DIR__,drel_grammar),String)
    parser = lark[:Lark](grammar_text,start="input",parser="lalr",lexer="contextual")
end

# Parse and output proto-Julia code using Python Lark. We cannot pass complex
# objects to Python, so we extract the needed information here.

lark_transformer(dname,dict,all_funcs,cat_list,func_cat) = begin
    # extract information to pass to python
    println("Now preparing dREL transformer for $dname")
    target_cat = String(dict[dname]["_name.category_id"][1])
    target_obj = String(dict[dname]["_name.object_id"][1])
    is_func = false
    if lowercase(target_cat) == lowercase.(func_cat)
        is_func = true
    end
    tt = jl_transformer[:TreeToPy](dname,target_cat,target_obj,cat_list,is_func=is_func,func_list=all_funcs)
end

#== Functions defined in the dictionary are detected and adjusted while parsing. To avoid
doing this every call, they are pre-processed here.
==#

get_cat_names(dict::cifdic) = begin
    catlist = [a for a in keys(dict) if String(get(dict[a],"_definition.scope",["Item"])[1]) == "Category"]
end

get_dict_funcs(dict::cifdic) = begin
    func_cat = [a for a in keys(dict) if String(get(dict[a],"_definition.class",["Datum"])[1]) == "Functions"]
    if length(func_cat) > 0
        func_catname = lowercase(String(dict[func_cat[1]]["_name.object_id"][1]))
        all_funcs = [a for a in keys(dict) if lowercase(String(dict[a]["_name.category_id"][1])) == func_catname]
        all_funcs = lowercase.([String(dict[a]["_name.object_id"][1]) for a in all_funcs])
    else
        all_funcs = []
    end
    return func_catname,all_funcs
end

get_drel_methods(cd::cifdic) = begin
    has_meth = [n for n in cd if "_method.expression" in keys(n) && String(get(n,"_definition.scope",["Item"])[1]) != "Category"]
    meths = [(String(n["_definition.id"][1]),get_loop(n,"_method.expression")) for n in has_meth]
    println("Found $(length(meths)) methods")
    return meths
end

#== This method creates Julia code from dREL code by
(1) parsing the drel text into a parse tree
(2) traversing the parse tree with a transformer that has been prepared
    with the crucial information to output syntactically-correct Julia code
(3) parsing the returned Julia code into an expression
(4) adjusting indices to 1-based
(5) changing any aliases of the main category back to the category name
(6) making sure that all local variables are defined at the top level
(7) turning set categories into packets
==#

make_julia_code(drel_text::String,dataname::String,dict::abstract_cif_dictionary,parser,all_funcs,func_cat,cat_names) = begin
    tree = parser[:parse](drel_text)
    transformer = lark_transformer(dataname,dict,all_funcs,cat_names,func_cat)
    tc_aliases,proto = transformer[:transform](tree)
    println("Proto-Julia code: ")
    println(proto)
    set_categories = get_set_categories(dict)
    parsed = ast_fix_indexing(Meta.parse(proto),Symbol.(["__packet"]))
    # catch implicit matrix assignments
    container_type = String(dict[dataname]["_type.container"][1])
    is_matrix = (container_type == "Matrix" || container_type == "Array")
    parsed = find_target(parsed,tc_aliases,transformer[:target_object];is_matrix=is_matrix)
    parsed = fix_scope(parsed)
    parsed = cat_to_packet(parsed,set_categories)  #turn Set categories into packets
end

#== Extract the dREL text from the dictionary
==#
get_func_text(dict::abstract_cif_dictionary,dataname::String) =  begin
    full_def = dict[dataname]
    func_text = get_loop(full_def,"_method.expression")
    # TODO: ignore non 'Evaluation' methods
    # TODO: allow multiple methods
    func_text = String(func_text[Symbol("_method.expression")][1])
end

#== A dynamic block uses the dREL code defined in the dictionary
in order to find missing values==#

struct dynamic_dict <: abstract_cif_dictionary
    dictionary::cifdic
    cat_names::Array{String,1}
    func_cat::String
    func_names::Array{String,1}

    dynamic_dict(c::cifdic) = begin
        #Parse and evaluate all dictionary-defined functions
        func_cat,all_funcs = get_dict_funcs(c)
        cat_names = get_cat_names(c)
        parser = lark_grammar()
        for f in all_funcs
            println("Now processing $f")         
            full_def = get_by_cat_obj(c,(func_cat,f))
            entry_name = String(full_def["_definition.id"][1])
            func_text = get_loop(full_def,"_method.expression")
            func_text = String(func_text[Symbol("_method.expression")][1])
            println("Function text: $func_text")
            result = make_julia_code(func_text,entry_name,c,parser,all_funcs,func_cat,cat_names)
            println("Transformed text: $result")
            eval(result)  #place function name in module scope
        end
        return new(c,cat_names,func_cat,all_funcs)
    end
end

dynamic_dict(s::String) = begin
    s = cifdic(s)
    return dynamic_dict(s)
end

Base.getindex(d::dynamic_dict,s::String) = d.dictionary[s]
Base.keys(d::dynamic_dict) = keys(d.dictionary)
JuliaCif.get_by_cat_obj(d::dynamic_dict,catobj) = get_by_cat_obj(d.dictionary,catobj)
JuliaCif.find_category(d::dynamic_dict,s) = find_category(d.dictionary,s)

struct dynamic_block <: cif_container_with_dict
    block::cif_block_with_dict
    dictionary::dynamic_dict
end

dynamic_block(b::NativeBlock,c::cifdic) = begin
    cbwd = assign_dictionary(b,c)
    dd = dynamic_dict(c)
    dynamic_block(cbwd,dd)
end

JuliaCif.get_datablock(b::dynamic_block) = b.block
JuliaCif.get_dictionary(b::dynamic_block) = b.dictionary

#== Initialise functions
==#
const func_lookup = Dict{String,Function}()

Base.getindex(d::dynamic_block,s::String) = begin
    try
        q = d.block[s]
    catch KeyError
        derive(d,s)
    end
end

#==Derive all values in a loop for the given
dataname==#

derive(d::dynamic_block,s::String) = begin
    if !(s in keys(func_lookup))
        add_new_func(get_dictionary(d),s)
    end
    func_name = func_lookup[s]
    target_loop = CategoryObject(d,find_category(get_dictionary(d),s))
    println("Now deriving $s in loop")
    for p in target_loop
        println("$(getfield(p,:dfr))")
    end
    [Base.invokelatest(func_name,d,get_dictionary(d),p) for p in target_loop]
end

#==This is called from within a dREL method when an item is
found missing from a packet==#

derive(d::dynamic_block,cat::String,obj::String,p::CatPacket) = begin
    dataname = String(get_by_cat_obj(get_dictionary(d),(cat,obj))["_definition.id"][1])
    if !(dataname in keys(func_lookup))
        add_new_func(get_dictionary(d),dataname)
    end
    func_name = func_lookup[dataname]
    Base.invokelatest(func_name,d,get_dictionary(d),p)
end

#== We redefine getproperty to allow derivation
==#

Base.getproperty(cp::CatPacket,obj::Symbol) = begin
    try
        return getproperty(getfield(cp,:dfr),obj)
    catch KeyError
        println("$(getfield(cp,:dfr)) has no member $obj:deriving...")
        # get the parent container with dictionary
        db = getfield(cp,:parent).datablock
        return derive(db,get_name(cp),String(obj),cp)
    end
end

add_new_func(d::dynamic_dict,s::String) = begin
    t = get_func_text(d,s)
    parser = lark_grammar()
    r = make_julia_code(t,s,d,parser,d.func_names,
                                  d.func_cat,d.cat_names)
    println("Transformed code for $s:\n")
    println(r)
    f = eval(r)
    merge!(func_lookup,Dict(s=>f))
end

    
end
