function csd(C::Int)
    addergraph = AdderGraph(Vector{Int}([C]))
    oddC = odd(C)
    if oddC == 1
        return addergraph
    end
    vect_csd = reverse(int2csd(oddC))
    newnode = AdderNode(2^(length(vect_csd)-1) + vect_csd[1],
        [InputEdge(get_origin(addergraph), length(vect_csd)-1, false),
        InputEdge(get_origin(addergraph), 0, vect_csd[1] == -1)]
    )
    push_node!(addergraph, newnode)
    for i in 2:(length(vect_csd)-1)
        if vect_csd[i] == 0
            continue
        end
        newnode = AdderNode(get_value(newnode) + vect_csd[i]*2^(i-1),
            [InputEdge(get_origin(addergraph), i-1, vect_csd[i] == -1),
            InputEdge(newnode, 0, false)]
        )
        push_node!(addergraph, newnode)
    end
    return addergraph
end

function csd(C::Vector{Int})
    addergraph = AdderGraph(C)
    addernode_vals = Vector{Int}()
    for val in C
        ag = csd(val)
        for addernode in get_nodes(ag)
            if !(get_value(addernode) in addernode_vals)
                push!(addernode_vals, get_value(addernode))
                push_node!(addergraph, addernode)
            end
        end
    end
    return addergraph

end
