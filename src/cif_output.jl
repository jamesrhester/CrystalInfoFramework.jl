# Routines for outputting CIF values

export format_for_cif

"""
`format_for_cif(val)`

Return a text string suitably delimited ready for output in
a CIF2 file. Will not handle pathological cases and does not
yet use the prefixing and line length protocols. No check of
content for correctness (yet).
"""
format_for_cif(val::String) = begin
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
            else
                q = match(r"\w+",val)
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
    for n in names(df)
        write(outstring,"  "*outname*String(n)*"\n")
    end
    line_pos = 1
    for one_row in eachrow(df)
        for n in names(df)
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
