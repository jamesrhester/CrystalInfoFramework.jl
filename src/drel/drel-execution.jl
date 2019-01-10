#== This module defines an environment for executing dREL code
==#

module drel_exec

export dynamic_dict

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
    tt = jl_transformer[:TreeToPy](dname,"myfunc",target_cat,target_obj,cat_list,is_func=is_func,func_list=all_funcs)
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

get_drel_methods(cd) = begin
    has_meth = [n for n in cd if "_method.expression" in keys(n) && String(get(n,"_definition.scope",["Item"])[1]) != "Category"]
    meths = [(String(n["_definition.id"][1]),get_loop(n,"_method.expression")) for n in has_meth]
    println("Found $(length(meths)) methods")
    return meths
end

make_julia_code(drel_text::String,dataname::String,dict::cifdic,parser,all_funcs,func_cat,cat_names) = begin
    tree = parser[:parse](drel_text)
    transformer = lark_transformer(dataname,dict,all_funcs,cat_names,func_cat)
    tc_aliases,proto = transformer[:transform](tree)
    parsed = ast_fix_indexing(Meta.parse(proto),Symbol.(["__packet"]))
    if tc_aliases != ""
        parsed = find_target(parsed,tc_aliases,transformer[:target_object])
    end
    parsed = fix_scope(parsed)
end

#== A dynamic block uses the dREL code defined in the dictionary
in order to find missing values==#

struct dynamic_dict
    dictionary::cifdic

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
            eval(result)
        end
        return new(c)
    end
end

dynamic_dict(s::String) = begin
    s = cifdic(s)
    println("Have ordinary dictionary")
    return dynamic_dict(s)
end

struct dynamic_block
    cif::NativeBlock
    dictionary::dynamic_dict
end

#== Initialise functions
==#


Base.getindex(d::dynamic_block,s::String) = begin
    try
        q = d.cif[s]
    catch KeyError
        derive(d,s)
    end
end

derive(d::dynamic_block,s::String) = begin
    
end
end
