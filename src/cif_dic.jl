# CIF Dictionaries

export Cifdic,get_by_cat_obj,assign_dictionary,get_julia_type,get_alias, is_alias
export cif_block_with_dict, abstract_cif_dictionary,cif_container_with_dict
export get_datablock,find_category,get_categories,get_set_categories
export get_typed_datablock
export translate_alias,list_aliases
export find_object,find_name
export get_single_key_cats
export get_names_in_cat,get_linked_names_in_cat,get_keys_for_cat
export get_objs_in_cat
export get_dict_funcs                   #List the functions in the dictionary
export get_parent_category,get_child_categories
export get_func,set_func!,has_func
export get_def_meth,get_def_meth_txt    #Methods for calculating defaults
export get_julia_type_name,get_loop_categories, get_dimensions, get_single_keyname
export get_ultimate_link
export get_default
export get_dic_name
export get_cat_class
export get_dic_namespace
export is_category

abstract type abstract_cif_dictionary end

# Methods that should be instantiated by concrete types

Base.keys(d::abstract_cif_dictionary) = begin
    error("Keys function should be defined for $(typeof(d))")
end

Base.length(d::abstract_cif_dictionary) = begin
    return length(keys(d))
end



