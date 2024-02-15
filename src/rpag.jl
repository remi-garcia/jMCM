function generate_rpag_cmd(v::Vector{Int}; with_register_cost::Bool=false, nb_extra_stages::Int=0)
    return "rpag $(with_register_cost ? "" : "--cost_model=hl_min_ad ")$(nb_extra_stages==0 ? "" : "--no_of_extra_stages=$(nb_extra_stages) ")"*join(v, " ")
end


function rpagcall(rpag_cmd::String; use_rpag_lib::Bool=false, kwargs...) # "rpag --cost_model=hl_min_ad 7 19 31"
    filename = tempname()
    argv = Vector{String}(string.(split(rpag_cmd)))
    open(filename, "w") do fileout
        redirect_stdout(fileout) do
            if use_rpag_lib
                ccall((:main, "librpag"), Cint, (Cint, Ptr{Ptr{UInt8}}), length(argv), argv)
                Base.Libc.flush_cstdio()
            else
                try
                    run(`$(argv)`)
                catch
                end
            end
        end
    end
    return read(filename, String)
end


function rpag(C::Vector{Int}; kwargs...)
    if isempty(Libc.find_library("librpag"))
        @warn "librpag not found"
        return AdderGraph()
    end
    s = split(rpagcall(generate_rpag_cmd(C; kwargs...), kwargs...), "\n")
    addergraph_str = ""
    for val in s
        if startswith(val, "pipelined_adder_graph=")
            addergraph_str = string(split(val, "=")[2])
        end
    end
    addergraph = read_addergraph(addergraph_str)
    return addergraph
end
