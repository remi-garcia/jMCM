function generate_rpag_cmd(v::Vector{Int})
    return "rpag --cost_model=hl_min_ad "*join(v, " ")
end


function rpagcall(rpag_cmd::String) # "rpag --cost_model=hl_min_ad 7 19 31"
    filename = tempname()
    argv = Vector{String}(string.(split(rpag_cmd)))
    open(filename, "w") do fileout
        redirect_stdout(fileout) do
            ccall((:main, "librpag"), Cint, (Cint, Ptr{Ptr{UInt8}}), length(argv), argv)
            Base.Libc.flush_cstdio()
        end
    end
    return read(filename, String)
end


function rpag(C::Vector{Int})
    if isempty(Libc.find_library("librpag"))
        @warn "librpag not found"
        return AdderGraph()
    end
    s = split(rpagcall(generate_rpag_cmd(C)), "\n")
    addergraph_str = ""
    for val in s
        if startswith(val, "pipelined_adder_graph=")
            addergraph_str = string(split(val, "=")[2])
        end
    end
    addergraph = read_addergraph(addergraph_str)
    return addergraph
end
