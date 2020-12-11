# **Routines for outputting CIF values

export format_for_cif

"""
    format_for_cif(val)

Format the provided value for output in a CIF2
file. Generally CIF1 and CIF2 syntaxes are
identical for non-text values.  CIF2 syntax
is preferred where the result is also conformant
CIF1 syntax with the same meaning.
"""
function format_for_cif end

"""
    format_for_cif(val::AbstractString;cif1=false)

Return `val` formatted as a text string for output in
a CIF2 file.  Line folding and prefixing is not used.

If `cif1`, triple-quoted strings
will never be output, but output will fail if the
supplied string contains the "\n;" digraph.  For `cif1`,
non-ASCII code points in `val` are output despite
this being a violation of the CIF1 standard.
"""
format_for_cif(val::AbstractString;cif1=false) = begin
    if '\n' in val
        if occursin("\n;",val)
            if cif1
                throw(error("$val cannot be formatted using CIF1 syntax"))
            end
            if occursin("'''",val)
                delimiter = "\"\"\""
            else
                delimiter = "'''"
            end
        else
            delimiter = "\n;"
        end
    else
        if '"' in val
            if '\'' in val
                delimiter = "\n;"
            else
                delimiter = "'"
            end
        else
            if '\'' in val
                delimiter = "\n;"
            elseif length(val) == 0
                delimiter = "'"
            elseif first(val) == '_'
                delimiter = "'"
            else
                q = match(r"^data|^save|^global|^loop",String(val))
                if !isnothing(q) delimiter = "'"
                else
                    q = match(r"\w+",String(val))
                    if !isnothing(q) && q.match == val delimiter = ""
                    else
                        delimiter = "'"
                    end
                end
            end
        end
    end
    return delimiter*val*delimiter
end

format_for_cif(val::Real) = begin
    return "$val"
end

format_for_cif(val::Missing) = "?"
format_for_cif(val::Nothing) = "."

format_for_cif(val::Array) = begin
    outstring = IOBuffer()
    write(outstring,"[")
    line_pos = 1
    for item in val
        value = format_for_cif(item)
        if '\n' in value
            line_pos = length(value) - findlast(isequal('\n'),value) + 1
            write(outstring, value)
            write(outstring, " ")
        else
            if length(value) + line_pos + 1 > 80
                write(outstring,"\n")
                write(outstring,value)
                line_pos = length(value)
            else
                write(outstring, " ")
                write(outstring, value)
                line_pos = line_pos + length(value) + 1
            end
        end
    end
    write(outstring,"]")
    return String(take!(outstring))
end

format_for_cif(val::Dict) = begin
    outstring = IOBuffer()
    write(outstring,"{")
    line_pos = 1
    for (k,v) in val
        mini_val = "'$k':$(format_for_cif(v))"
        if '\n' in mini_val
            line_pos = length(mini_val) - findlast(isequal('\n'),mini_val) + 1
            write(outstring, mini_val)
            write(outstring, " ")
        else
            if length(mini_val) + line_pos + 1 > 80
                write(outstring,"\n")
                write(outstring,mini_val)
                line_pos = length(mini_val)
            else
                write(outstring, " ")
                write(outstring, mini_val)
                line_pos = line_pos + length(mini_val) + 1
            end
        end
    end
    write(outstring,"}")
    return String(take!(outstring))
end

"""
If passed a DataFrame we format a loop. If passed an additional name for
the category, each column name is prefixed by this name
"""
format_for_cif(df::DataFrame;catname=nothing) = begin
    outstring = IOBuffer()
    write(outstring,"loop_\n")
    outname = ""
    if catname != nothing
        outname = "_"*catname*"."
    end
    # remove missing columns
    for n in names(df)
        if all(x->ismissing(x),df[!,n]) continue end
        write(outstring,"  "*outname*String(n)*"\n")
    end
    line_pos = 1
    for one_row in eachrow(df)
        for n in names(df)
            if all(x->ismissing(x),df[!,n]) continue end
            new_val = format_for_cif(getproperty(one_row,n))
            if '\n' in new_val   # assume will start a new line
                line_pos = length(new_val) - findlast(isequal('\n'),new_val)
                write(outstring,new_val)
            else
                if length(new_val) + line_pos + 2 > 80
                    write(outstring,"\n")
                    line_pos = 1
                    write(outstring,new_val)
                    line_pos = line_pos + length(new_val)
                else
                    write(outstring,"  ")
                    write(outstring,new_val)
                    line_pos = line_pos + length(new_val) + 2
                end
            end
        end
        write(outstring,"\n")
        line_pos = 1
    end
    String(take!(outstring))
end

"""
    show_one_def(io,def_name,info_dic;implicits=[])

Convert one dictionary definition for `def_name` to text. 
`info_dic` is a dictionary of `DataFrame`s for each DDL
category appearing in the definition. `implicits`
is a list of `category.column` names that should not be
printed. No underscore appears before the category
name.
"""
show_one_def(io,def_name,info_dic;implicits=[]) = begin
    write(io,"\nsave_$def_name\n\n")
    for (cat,df) in info_dic
        if nrow(df) == 0 continue end
        if nrow(df) == 1 show_set(io,cat,df,implicits=implicits) end
        if nrow(df) > 1 show_loop(io,String(cat),df,implicits=implicits) end
    end
    write(io,"\nsave_\n")
end

# We can skip defaults

"""
    show_set(io,cat,df;implicits=[])

Format the contents of single-row DataFrame `df` as a series
of key-value pairs in CIF syntax.
"""
show_set(io,cat,df;implicits=[]) = begin
    colnames = sort!(propertynames(df))
    for cl in colnames
        if cl in [:master_id,:__blockname,:__object_id] continue end
        if "$cat.$(String(cl))" in implicits continue end
        this_val = df[!,cl][]
        if ismissing(this_val) continue end
        if haskey(ddlm_defaults,(cat,cl)) && ddlm_defaults[(cat,cl)] == this_val continue end
        Printf.@printf(io,"%-40s\t%s\n","_$cat.$cl","$(format_for_cif(this_val))")
    end
end

"""
    show_loop(io,cat,df;implicits=[])

Format the contents of multi-row DataFrame `df` as a CIF loop.
 If `cat.col` appears in `implicits` then `col` is not output.
"""
show_loop(io,cat,df;implicits=[]) = begin
    if nrow(df) == 0 return end
    rej_names = filter(x->split(x,".")[1]==cat,implicits)
    rej_names = map(x->split(x,".")[2],rej_names)
    append!(rej_names,["master_id","__blockname","__object_id"])
    imp_reg = Regex("$(join(rej_names,"|^"))")
    write(io,format_for_cif(df[!,Not(imp_reg)];catname=cat))
end       

"""
    show(io::IO,::MIME"text/cif",c::Cif)

Write the contents of `c` as a CIF file to `io`.
"""
show(io::IO,::MIME"text/cif",c::Cif) = begin
    for k in keys(c)
        write(io,"data_$k\n")
        show(io,MIME("text/cif"),c[k])
    end
end

Base.show(io::IO,::MIME"text/cif",c::CifContainer) = begin
    write(io,"\n")
    key_vals = setdiff(collect(keys(c)),get_loop_names(c)...)
    for k in key_vals
        item = format_for_cif(first(c[k]))
        write(io,"$k\t$item\n")
    end
    
    # now go through the loops
    for one_loop in get_loop_names(c)
        a_loop = get_loop(c,first(one_loop))
        write(io,format_for_cif(a_loop))
    end
end

Base.show(io::IO,::MIME"text/cif",b::NestedCifContainer) = begin
    # first output the save frames
    show(io,get_frames(b))
    show(io,Block(b))
end
     
"""
    show(io::IO,::MIME"text/cif",ddlm_dic::DDLm_Dictionary)

Output `ddlm_dic` in CIF format.
"""
show(io::IO,::MIME"text/cif",ddlm_dic::DDLm_Dictionary) = begin
    dicname = ddlm_dic[:dictionary].title[]
    write(io,"#\\#CIF_2.0\n")
    write(io,"""
##############################################################
#
#        $dicname (DDLm)
#
##############################################################\n""")
    write(io,"data_$dicname\n")
    top_level = ddlm_dic[:dictionary]
    show_set(io,"dictionary",top_level)
    # And the unlooped top-level stuff
    top_level = ddlm_dic[dicname]
    for c in keys(top_level)
        if c == :dictionary continue end
        if nrow(top_level[c]) == 1
            show_set(io,String(c),top_level[c])
        end
    end
    # Now for the rest
    head = find_head_category(ddlm_dic)
    show_one_def(io,head,ddlm_dic[head])
    all_cats = sort!(get_categories(ddlm_dic))
    for one_cat in all_cats
        if one_cat == head continue end
        cat_info = ddlm_dic[one_cat]
        show_one_def(io,one_cat,cat_info)
        items = get_names_in_cat(ddlm_dic,one_cat)
        for one_item in items
            show_one_def(io,one_item,ddlm_dic[one_item])
        end
    end
    # And the looped top-level stuff
    top_level = ddlm_dic[dicname]
    for c in keys(top_level)
        if c == :dictionary continue end
        if nrow(top_level[c]) > 1
            show_loop(io,String(c),top_level[c])
        end
    end
end

     
#
# **Output**
#
# DDL2 makes use of implicit values based on the block name. We
# ignore any columns contained in the 'implicit' const.
#

"""
    show(io::IO,::MIME"text/cif",ddl2_dic::DDL2_Dictionary)

Output `ddl2_dic` in CIF format.
"""
show(io::IO,::MIME"text/cif",ddl2_dic::DDL2_Dictionary) = begin
    dicname = ddl2_dic[:dictionary].title[]
    write(io,"#")
    write(io,"""
##############################################################
#
#        $dicname (DDL2)
#
##############################################################\n""")
    write(io,"data_$dicname\n")
    implicit_info = get_implicit_list()
    top_level = ddl2_dic[:datablock]
    show_set(io,"datablock",top_level,implicits=implicit_info)
    top_level = ddl2_dic[:dictionary]
    show_set(io,"dictionary",top_level,implicits=implicit_info)
    # Now for the rest
    all_cats = sort(get_categories(ddl2_dic))
    for one_cat in all_cats
        cat_info = ddl2_dic[one_cat]
        show_one_def(io,one_cat,cat_info,implicits=implicit_info)
        items = get_names_in_cat(ddl2_dic,one_cat)
        for one_item in items
            show_one_def(io,one_item,ddl2_dic[one_item],implicits=implicit_info)
        end
    end
    # And the looped top-level stuff
    for c in [:item_units_conversion,:item_units_list,:item_type_list,:dictionary_history]
        if c in keys(ddl2_dic.block) && nrow(ddl2_dic[c]) > 0
            show_loop(io,String(c),ddl2_dic[c],implicits=implicit_info)
        end
    end
end
