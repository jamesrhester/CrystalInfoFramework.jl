# **Routines for outputting CIF values

export format_for_cif

"""
    format_for_cif(val)

Return `val` formatted as a text string for output in
a CIF2 file. May not handle pathological cases and does not
yet use the prefixing and line length protocols.
"""
format_for_cif(val::AbstractString) = begin
    if '\n' in val
        if occursin("\n;",val)
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
            elseif first(val) == "_"
                delimiter = "'"
            else
                q = match(r"\w+",String(val))
                if !isnothing(q) && q.match == val delimiter = ""
                else
                    delimiter = "'"
                end
            end
        end
    end
    return delimiter*val*delimiter
end

format_for_cif(val::Integer) = begin
    return "$val"
end

# TODO: take account of SU and truncate
format_for_cif(val::Float64) = begin
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
        mini_val = "$k:$(format_for_cif(v))"
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
