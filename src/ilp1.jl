#using JuMP


"""
role:



input:
output:





"""
function model_mcm_forumlation!(model::Model, C::Vector{Int},
                                wordlength::Int,
                                NA::Int;
                                use_all_adders::Bool=false,
                                adder_depth_max::Int=0,
                                minimize_adder_depth::Bool=false,
                                minimize_one_bit_depth::Bool=false,
                                minimize_adder_cost::Bool=false,
                                minimize_critical_path::Bool=false,
                                wordlength_in::Int=0,
                                no_one_bit_adders::Bool=false,
                                input_error::Int=0,
                                output_errors::Vector{Int},
                                verbose::Bool=false,
                                known_min_NA::Int=0,
                                with_pipelining_cost::Bool,
                                adder_cost::Union{Int, Float64}=1,
                                register_cost::Union{Int, Float64}=1,
                                max_dsp::Int=0,
                                one_is_output::Bool=false,
                                addergraph_warmstart::AdderGraph,
                                use_big_m::Bool=true,
                                no_right_shifts::Bool=false,
                                ws_values::Dict{String, Float64}=Dict{String, Float64}(),
                                kwargs...
    )::Model
    if no_one_bit_adders
        wordlength_in = 0
    end
    if minimize_critical_path
        if wordlength_in == 0
            minimize_adder_depth = true
        else
            minimize_one_bit_depth = true
        end
        if with_pipelining_cost && wordlength_in != 0
            minimize_adder_cost = true
        end
    end
    addernodes = Vector{AdderNode}()
    addernodes_value_to_index = Dict{Tuple{Int, Int}, Int}()
    nb_var_warmstart = 0
    use_warmstart = false
    if !isempty(addergraph_warmstart)
        use_warmstart = true
        addernodes = get_nodes(addergraph_warmstart)
        for addernode in addernodes
            sort!(addernode.inputs, by=x->x.shift, rev=true)
        end
        addernodes_value_to_index = Dict{Tuple{Int, Int}, Int}([(get_value(addernodes[i]), get_depth(addernodes[i])) => i for i in 1:length(addernodes)])
        addernodes_value_to_index[(1, 0)] = 0
        nb_var_warmstart = length(addernodes)
        verbose && println("Number of adders in warm start: $(nb_var_warmstart)")
        verbose && println("Warmstart adder graph: $(write_addergraph(addergraph_warmstart))")
        if nb_var_warmstart > NA
            @warn "Warm start cannot be used"
            nb_var_warmstart = NA
        end
    end
    Smin, Smax = -wordlength, wordlength
    if no_right_shifts
        Smin = 0
    end
    NO = length(C)
    known_min_NA = min(NA, max(get_min_number_of_adders(C), known_min_NA))
    # Do not use this model if no adders are used: known_min_NA >= 1
    known_min_NA = max(1, known_min_NA-max_dsp)
    if use_all_adders
        known_min_NA = NA
    end
    verbose && println("\tBounds on the number of adder: $(known_min_NA)--$(NA)")
    verbose && println("\tBounds on the number of DSPs: $(max_dsp)")
    if max_dsp > 0
        @warn "Currently, we assume that we can map any constant to a DSP."
    end
    maximum_target = maximum(C)
    maximum_value = 2^wordlength

    verbose && with_pipelining_cost && println("adder cost: $adder_cost -- register cost: $register_cost")

    @variable(model, 1 <= ca[0:NA] <= maximum_value-1, Int)
    @constraint(model, [a in 1:known_min_NA], ca[a] >= 3)
    @variable(model, 1 <= ca_no_shift[1:NA] <= maximum_value*2, Int)
    @variable(model, 1 <= cai[1:NA, 1:2] <= maximum_value-1, Int)
    @variable(model, 1 <= cai_left_sh[1:NA] <= maximum_value*2, Int)
    @variable(model, -2*maximum_value <= cai_left_shsg[1:NA] <= maximum_value*2, Int)
    @variable(model, -2*maximum_value <= cai_right_sg[1:NA] <= maximum_value*2, Int)

    @variable(model, Phiai[1:NA, 1:2], Bin)
    @variable(model, caik[a in 1:NA, 1:2, 0:(a-1)], Bin)
    @variable(model, phias[1:NA, 0:Smax], Bin)
    @variable(model, oaj[1:NA, 1:NO], Bin)

    model[:has_ada] = false
    if minimize_adder_depth || adder_depth_max != 0 || with_pipelining_cost
        model[:has_ada] = true
        # Add adder depth
        @variable(model, 0 <= ada[0:NA] <= NA)
        fix(ada[0], 0, force=true)
        @variable(model, 1 <= max_ad <= NA, Int)
        @constraint(model, [a in 1:NA, i in 1:2, k in 0:(a-1)], ada[a] >= ada[k]+1 - (1-caik[a,i,k])*NA)
        @constraint(model, [a in 1:NA], max_ad >= ada[a])

        if adder_depth_max != 0
            @constraint(model, max_ad <= adder_depth_max)
        end
    end

    @variable(model, 0 <= force_odd[1:NA] <= maximum_value, Int)
    @variable(model, Psias[1:NA, Smin:0], Bin)

    # C1
    fix(ca[0], 1, force=true)
    # C2 - Modified
    @constraint(model, [a in 1:NA], ca_no_shift[a] == cai_left_shsg[a] + cai_right_sg[a])
    # C3a - C3b
    @constraint(model, [a in 1:NA, i in 1:2, k in 0:(a-1)], cai[a,i] <= ca[k] + (1-caik[a,i,k])*maximum_value)
    @constraint(model, [a in 1:NA, i in 1:2, k in 0:(a-1)], cai[a,i] >= ca[k] - (1-caik[a,i,k])*maximum_value)
    @constraint(model, [a in 1:NA, i in 1:2], sum(caik[a,i,k] for k in 0:(a-1)) == 1)
    # C4a - C4b - Modified
    @constraint(model, [a in 1:NA, s in 0:Smax], cai_left_sh[a] <= 2^s*cai[a,1] + (1-phias[a,s])*2*maximum_value)
    @constraint(model, [a in 1:NA, s in 0:Smax], cai_left_sh[a] >= 2^s*cai[a,1] - (1-phias[a,s])*(2*maximum_value*(2^s)))
    @constraint(model, [a in 1:NA], sum(phias[a,s] for s in 0:Smax) == 1)
    # C5a - C5b - C5c - Modified
    @constraint(model, [a in 1:NA], cai_left_shsg[a] <= cai_left_sh[a] + Phiai[a,1]*2*maximum_value)
    @constraint(model, [a in 1:NA], cai_left_shsg[a] >= cai_left_sh[a] - Phiai[a,1]*(4*maximum_value))
    @constraint(model, [a in 1:NA], cai_left_shsg[a] <= -cai_left_sh[a] + (1-Phiai[a,1])*(4*maximum_value))
    @constraint(model, [a in 1:NA], cai_left_shsg[a] >= -cai_left_sh[a] - (1-Phiai[a,1])*2*maximum_value)
    @constraint(model, [a in 1:NA], cai_right_sg[a] <= cai[a,2] + Phiai[a,2]*maximum_value)
    @constraint(model, [a in 1:NA], cai_right_sg[a] >= cai[a,2] - Phiai[a,2]*(2*maximum_value))
    @constraint(model, [a in 1:NA], cai_right_sg[a] <= -cai[a,2] + (1-Phiai[a,2])*(2*maximum_value))
    @constraint(model, [a in 1:NA], cai_right_sg[a] >= -cai[a,2] - (1-Phiai[a,2])*maximum_value)
    @constraint(model, [a in 1:NA], Phiai[a,1] + Phiai[a,2] <= 1)
    # C6a - C6b
    if max_dsp == 0
        @constraint(model, [a in 1:NA, j in 1:NO], ca[a] <= C[j] + (1-oaj[a,j])*maximum_value)
        @constraint(model, [a in 1:NA, j in 1:NO], ca[a] >= C[j] - (1-oaj[a,j])*maximum_target)
        @constraint(model, [j in 1:NO], sum(oaj[a,j] for a in 1:NA) == 1)
    else
        @variable(model, use_dsp[1:NO], Bin)
        @constraint(model, [a in 1:NA, j in 1:NO], ca[a] <= C[j] + (1-oaj[a,j])*maximum_value + (1-use_dspj[j])*maximum_value)
        @constraint(model, [a in 1:NA, j in 1:NO], ca[a] >= C[j] - (1-oaj[a,j])*maximum_target - (1-use_dspj[j])*maximum_target)
        @constraint(model, [j in 1:NO], sum(oaj[a,j] for a in 1:NA)+use_dspj[j] == 1)
        @constraint(model, sum(use_dspj) <= max_dsp)
    end

    # Odd
    @constraint(model, [a in 1:NA], ca[a] == 2*force_odd[a]+1)
    @constraint(model, [a in 1:NA, s in Smin:0], ca_no_shift[a] >= 2^(-s)*ca[a] + (Psias[a,s] - 1)*(maximum_value*(2^(-s))))
    @constraint(model, [a in 1:NA, s in Smin:0], ca_no_shift[a] <= 2^(-s)*ca[a] + (1 - Psias[a,s])*(maximum_value*(2^(-s))))
    @constraint(model, [a in 1:NA], sum(Psias[a,s] for s in Smin:0) == 1)
    @constraint(model, [a in 1:NA], phias[a,0] == sum(Psias[a,s] for s in Smin:0)-Psias[a,0])

    max_wordlength = 0
    if wordlength_in > 0
        max_wordlength = round(Int, log2((2^wordlength - 1)*(2^wordlength_in - 1)), RoundUp)
        truncate_max = max_wordlength # Mock value
        max_output_error = maximum(output_errors) # Should be a parameter

        @variable(model, 0 <= onebit_a_used[1:NA] <= max_wordlength, Int)
        @variable(model, 0 <= onebit_a[1:NA] <= max_wordlength, Int)
        @variable(model, 0 <= g_a[1:NA] <= max_wordlength-1, Int)
        @variable(model, 0 <= wordlength_a[0:NA] <= max_wordlength, Int)
        @variable(model, psi_a[1:NA], Bin)

        @variable(model, 0 <= adder_input_pos_bitshift[1:NA] <= Smax, Int)
        @constraint(model, [a in 1:NA], adder_input_pos_bitshift[a] == sum(s*phias[a,s] for s in 1:Smax))
        @constraint(model, [a in 1:NA, s in 0:Smax], adder_input_pos_bitshift[a] >= s - (1-phias[a,s])*Smax)
        @constraint(model, [a in 1:NA, s in 0:Smax], adder_input_pos_bitshift[a] <= s + (1-phias[a,s])*Smax)
        @variable(model, Smin <= adder_neg_bitshift[1:NA] <= 0, Int)
        @constraint(model, [a in 1:NA], adder_neg_bitshift[a] == sum(s*Psias[a,s] for s in Smin:0))
        @constraint(model, [a in 1:NA, s in Smin:0], adder_neg_bitshift[a] >= s + (1-Psias[a,s])*Smin)
        @constraint(model, [a in 1:NA, s in Smin:0], adder_neg_bitshift[a] <= s - (1-Psias[a,s])*Smin)

        @constraint(model, [a in 1:NA], onebit_a[a] == wordlength_a[a] - g_a[a] + psi_a[a] - 1 - adder_neg_bitshift[a])
        @constraint(model, [a in 1:NA], g_a[a] <= wordlength_a[a])

        @variable(model, fourthcase[1:NA], Bin)
        @variable(model, whichcase[1:NA], Bin)
        @constraint(model, [a in 1:NA], whichcase[a] >= Phiai[a,1]) # if Phiai[a,1] == 1 we want whichcase to be 1
        @constraint(model, [a in 1:NA], whichcase[a] <= 1-Phiai[a,2]) # if Phiai[a,2] == 1 we want whichcase to be 0
        @constraint(model, [a in 1:NA], fourthcase[a] == phias[a,0])

        @constraint(model, [a in 1:NA], g_a[a] <= (1-fourthcase[a])*max_wordlength)

        @variable(model, 0 <= wordlength_left[1:NA] <= max_wordlength, Int)
        @variable(model, 0 <= wordlength_right[1:NA] <= max_wordlength, Int)
        if max_output_error != 0
            # Counting zeros in data
            @variable(model, 0 <= adder_zeros[0:NA] <= max_wordlength, Int)
            fix(adder_zeros[0], 0, force=true)
            @variable(model, 0 <= left_zeros[1:NA] <= max_wordlength, Int)
            @variable(model, 0 <= right_zeros[1:NA] <= max_wordlength, Int)
            @variable(model, left_zeros_bit[1:NA, 0:max_wordlength], Bin)
            @variable(model, right_zeros_bit[1:NA, 0:max_wordlength], Bin)
            @constraint(model, [a in 1:NA], sum(left_zeros_bit[a, w] for w in 0:max_wordlength) == 1)
            @constraint(model, [a in 1:NA], sum(right_zeros_bit[a, w] for w in 0:max_wordlength) == 1)
            @constraint(model, [a in 1:NA], sum(w*left_zeros_bit[a, w] for w in 0:max_wordlength) == left_zeros[a])
            @constraint(model, [a in 1:NA], sum(w*right_zeros_bit[a, w] for w in 0:max_wordlength) == right_zeros[a])

            @constraint(model, [a in 1:NA, k in 0:(a-1)], left_zeros[a] <= adder_zeros[k] + (1-caik[a,1,k])*maximum_value)
            @constraint(model, [a in 1:NA, k in 0:(a-1)], left_zeros[a] >= adder_zeros[k] - (1-caik[a,1,k])*maximum_value)
            @constraint(model, [a in 1:NA, k in 0:(a-1)], right_zeros[a] <= adder_zeros[k] + (1-caik[a,2,k])*maximum_value)
            @constraint(model, [a in 1:NA, k in 0:(a-1)], right_zeros[a] >= adder_zeros[k] - (1-caik[a,2,k])*maximum_value)

            # Truncate part
            @variable(model, 0 <= internal_neg_error[0:NA] <= max_output_error, Int)
            @variable(model, 0 <= internal_pos_error[0:NA] <= max_output_error, Int)
            @variable(model, internal_neg_error_noshifted[1:NA] >= 0, Int)
            @variable(model, internal_neg_error_input_left_nonshifted[1:NA] >= 0, Int)
            @variable(model, internal_neg_error_input_right_nonshifted[1:NA] >= 0, Int)
            @variable(model, internal_neg_error_input_left[1:NA] >= 0, Int)
            @variable(model, internal_neg_error_input_right[1:NA] >= 0, Int)
            @variable(model, internal_neg_error_input_left_trunc[1:NA] >= 0, Int)
            @variable(model, internal_neg_error_input_right_trunc[1:NA] >= 0, Int)
            @variable(model, internal_pos_error_noshifted[1:NA] >= 0, Int)
            @variable(model, internal_pos_error_input_left_nonshifted[1:NA] >= 0, Int)
            @variable(model, internal_pos_error_input_right_nonshifted[1:NA] >= 0, Int)
            @variable(model, internal_pos_error_input_left[1:NA] >= 0, Int)
            @variable(model, internal_pos_error_input_right[1:NA] >= 0, Int)
            @variable(model, internal_pos_error_input_left_trunc[1:NA] >= 0, Int)
            @variable(model, internal_pos_error_input_right_trunc[1:NA] >= 0, Int)

            @variable(model, truncateleft[1:NA] >= 0, Int)
            @variable(model, truncateright[1:NA] >= 0, Int)
            @variable(model, truncateleft_bit[1:NA, 0:truncate_max], Bin)
            @variable(model, truncateright_bit[1:NA, 0:truncate_max], Bin)
            @variable(model, truncate_shift[1:NA, 0:truncate_max, 0:Smax], Bin)
            @constraint(model, [a in 1:NA], truncateleft[a] <= wordlength_a[a])
            @constraint(model, [a in 1:NA], truncateright[a] <= wordlength_a[a])

            @constraint(model, [a in 1:NA], sum(truncateleft_bit[a, w] for w in 0:truncate_max) == 1)
            @constraint(model, [a in 1:NA], sum(truncateright_bit[a, w] for w in 0:truncate_max) == 1)

            @constraint(model, [a in 1:NA], sum(w*truncateleft_bit[a, w] for w in 0:truncate_max) == truncateleft[a])
            @constraint(model, [a in 1:NA], sum(w*truncateright_bit[a, w] for w in 0:truncate_max) == truncateright[a])

            @constraint(model, internal_neg_error[0] == input_error)
            @constraint(model, internal_pos_error[0] == input_error)

            @constraint(model, [a in 1:NA, k in 0:(a-1)], internal_neg_error_input_left_nonshifted[a] >= internal_neg_error[k] - (1-caik[a,1,k])*max_output_error)
            @constraint(model, [a in 1:NA, k in 0:(a-1)], internal_neg_error_input_right_nonshifted[a] >= internal_neg_error[k] - (1-caik[a,2,k])*max_output_error)
            @constraint(model, [a in 1:NA, s in 0:Smax], internal_neg_error_input_left[a] >= 2.0^s*internal_neg_error_input_left_nonshifted[a]-(1-phias[a,s])*(max_output_error*(2.0^s)))
            @constraint(model, [a in 1:NA], internal_neg_error_input_right[a] >= internal_neg_error_input_right_nonshifted[a])
            @constraint(model, [a in 1:NA, s in Smin:0], 2^(-s)*internal_neg_error[a] >= internal_neg_error_noshifted[a] - (1-Psias[a,s])*(max_output_error*(2^(-s+Smax))))
            @constraint(model, [a in 1:NA, k in 0:(a-1)], internal_pos_error_input_left_nonshifted[a] >= internal_pos_error[k] - (1-caik[a,1,k])*max_output_error)
            @constraint(model, [a in 1:NA, k in 0:(a-1)], internal_pos_error_input_right_nonshifted[a] >= internal_pos_error[k] - (1-caik[a,2,k])*max_output_error)
            @constraint(model, [a in 1:NA, s in 0:Smax], internal_pos_error_input_left[a] >= 2.0^s*internal_pos_error_input_left_nonshifted[a]-(1-phias[a,s])*(max_output_error*(2.0^s)))
            @constraint(model, [a in 1:NA], internal_pos_error_input_right[a] >= internal_pos_error_input_right_nonshifted[a])
            @constraint(model, [a in 1:NA, s in Smin:0], 2^(-s)*internal_pos_error[a] >= internal_pos_error_noshifted[a] - (1-Psias[a,s])*(max_output_error*(2^(-s+Smax))))

            @constraint(model, [a in 1:NA, w in 0:truncate_max, s in 0:Smax], truncate_shift[a, w, s] >= truncateleft_bit[a, w]+phias[a, s]-1)
            @constraint(model, [a in 1:NA], sum(truncate_shift[a, :, :]) == 1)
            @constraint(model, [a in 1:NA], internal_neg_error_input_left_trunc[a] >= internal_neg_error_input_left[a])
            @constraint(model, [a in 1:NA, w in 1:truncate_max, s in 0:Smax], internal_neg_error_input_left_trunc[a] >= internal_neg_error_input_left[a] + (2.0^(w+s))*truncateleft_bit[a, w] - (1-truncate_shift[a, w, s])*(2.0^(truncate_max+Smax)) - sum((2.0^(ws+s))*left_zeros_bit[a, ws] for ws in 0:max_wordlength))
            @constraint(model, [a in 1:NA], internal_neg_error_input_right_trunc[a] >= internal_neg_error_input_right[a])
            @constraint(model, [a in 1:NA], internal_neg_error_input_right_trunc[a] >= internal_neg_error_input_right[a] + sum((2.0^(w))*truncateright_bit[a, w] for w in 1:truncate_max) - sum((2.0^(w))*right_zeros_bit[a, w] for w in 0:max_wordlength))
            # Phiai = 0 => pos # Phiai = 1 => neg
            @constraint(model, [a in 1:NA], internal_neg_error_noshifted[a] >= internal_neg_error_input_left_trunc[a]+internal_neg_error_input_right_trunc[a] - (Phiai[a,1]+Phiai[a,2])*2*max_output_error)
            @constraint(model, [a in 1:NA], internal_neg_error_noshifted[a] >= internal_neg_error_input_left_trunc[a]+internal_pos_error_input_right_trunc[a] - (Phiai[a,1])*max_output_error - (1-Phiai[a,2])*max_output_error)
            @constraint(model, [a in 1:NA], internal_neg_error_noshifted[a] >= internal_pos_error_input_left_trunc[a]+internal_neg_error_input_right_trunc[a] - (1-Phiai[a,1])*max_output_error - (Phiai[a,2])*max_output_error)
            # Truncatures do not increase the positive error
            @constraint(model, [a in 1:NA], internal_pos_error_input_left_trunc[a] == internal_pos_error_input_left[a])
            @constraint(model, [a in 1:NA], internal_pos_error_input_right_trunc[a] == internal_pos_error_input_right[a])
            # Phiai = 0 => pos # Phiai = 1 => neg
            @constraint(model, [a in 1:NA], internal_pos_error_noshifted[a] >= internal_pos_error_input_left_trunc[a]+internal_pos_error_input_right_trunc[a] - (Phiai[a,1]+Phiai[a,2])*2*max_output_error)
            @constraint(model, [a in 1:NA], internal_pos_error_noshifted[a] >= internal_pos_error_input_left_trunc[a]+internal_neg_error_input_right_trunc[a] - (Phiai[a,1])*max_output_error - (1-Phiai[a,2])*max_output_error)
            @constraint(model, [a in 1:NA], internal_pos_error_noshifted[a] >= internal_neg_error_input_left_trunc[a]+internal_pos_error_input_right_trunc[a] - (1-Phiai[a,1])*max_output_error - (Phiai[a,2])*max_output_error)

            @constraint(model, [a in 1:NA, j in 1:NO], internal_neg_error[a] <= output_errors[j] + (1-oaj[a,j])*max_output_error)
            @constraint(model, [a in 1:NA, j in 1:NO], internal_pos_error[a] <= output_errors[j] + (1-oaj[a,j])*max_output_error)

            @variable(model, 0 <= truncate_left_or_zeros[1:NA] <= max_wordlength, Int)
            @variable(model, truncate_left_or_zeros_switch[1:NA], Bin)
            @variable(model, 0 <= truncate_right_or_zeros[1:NA] <= max_wordlength, Int)
            @variable(model, truncate_right_or_zeros_switch[1:NA], Bin)
            @constraint(model, [a in 1:NA], truncate_left_or_zeros[a] <= truncateleft[a] + truncate_left_or_zeros_switch[a]*max_wordlength)
            @constraint(model, [a in 1:NA], truncate_left_or_zeros[a] <= left_zeros[a] + (1-truncate_left_or_zeros_switch[a])*max_wordlength)
            @constraint(model, [a in 1:NA], truncate_right_or_zeros[a] <= truncateright[a] + truncate_right_or_zeros_switch[a]*max_wordlength)
            @constraint(model, [a in 1:NA], truncate_right_or_zeros[a] <= right_zeros[a] + (1-truncate_right_or_zeros_switch[a])*max_wordlength)

            @constraint(model, [a in 1:NA], g_a[a] <= (truncate_left_or_zeros[a]+adder_input_pos_bitshift[a])+(1-whichcase[a])*max_wordlength)
            @constraint(model, [a in 1:NA], g_a[a] <= truncate_right_or_zeros[a]+whichcase[a]*max_wordlength)

            @constraint(model, [a in 1:NA], adder_zeros[a] <= truncateleft[a] + adder_input_pos_bitshift[a])
            @constraint(model, [a in 1:NA], adder_zeros[a] <= truncateright[a])

            @constraint(model, [a in 1:NA], truncateleft[a] <= wordlength_left[a])
            @constraint(model, [a in 1:NA], truncateright[a] <= wordlength_right[a])

            @variable(model, truncaterightorleft[1:NA], Bin)
            @constraint(model, [a in 1:NA], truncateleft[a] <= max_wordlength*truncaterightorleft[a])
            @constraint(model, [a in 1:NA], truncateright[a] <= max_wordlength*(1-truncaterightorleft[a]))
        else
            @constraint(model, [a in 1:NA], g_a[a] <= adder_input_pos_bitshift[a]+(1-whichcase[a])*max_wordlength)
            @constraint(model, [a in 1:NA], g_a[a] <= whichcase[a]*max_wordlength)
        end

        @constraint(model, wordlength_a[0] == wordlength_in)
        @constraint(model, [a in 1:NA, k in 0:(a-1)], wordlength_left[a] >= wordlength_a[k] - (1-caik[a,1,k])*max_wordlength)
        @constraint(model, [a in 1:NA, k in 0:(a-1)], wordlength_right[a] >= wordlength_a[k] - (1-caik[a,2,k])*max_wordlength)
        @constraint(model, [a in 1:NA, k in 0:(a-1)], wordlength_left[a] <= wordlength_a[k] + (1-caik[a,1,k])*max_wordlength)
        @constraint(model, [a in 1:NA, k in 0:(a-1)], wordlength_right[a] <= wordlength_a[k] + (1-caik[a,2,k])*max_wordlength)

        @constraint(model, [a in 1:NA], wordlength_a[a] >= wordlength_left[a]+adder_input_pos_bitshift[a]+adder_neg_bitshift[a]-1-(Phiai[a,1]+Phiai[a,2])*max_wordlength)
        @constraint(model, [a in 1:NA], wordlength_a[a] >= wordlength_right[a]+adder_neg_bitshift[a]-1-(Phiai[a,1]+Phiai[a,2])*max_wordlength)

        @constraint(model, [a in 1:NA], wordlength_left[a] + adder_input_pos_bitshift[a] + adder_neg_bitshift[a] + 1 <= wordlength_a[a] + psi_a[a]*(2*max_wordlength))
        @constraint(model, [a in 1:NA], wordlength_right[a] + adder_neg_bitshift[a] + 1 <= wordlength_a[a] + psi_a[a]*(2*max_wordlength))

        @variable(model, wordlength_ai[1:NA, 0:max_wordlength], Bin)
        @constraint(model, [a in 1:NA], wordlength_a[a] == sum(i*wordlength_ai[a, i] for i in 1:max_wordlength))
        @constraint(model, [a in 1:NA], sum(wordlength_ai[a, i] for i in 0:max_wordlength) == 1)
        @variable(model, 0 <= twopowerwordlength[1:NA] <= 2.0^(max_wordlength))

        @constraint(model, [a in 1:NA, i in 0:max_wordlength], twopowerwordlength[a] <= 2.0^(i)+(1-wordlength_ai[a, i])*2.0^max_wordlength)
        @constraint(model, [a in 1:NA], twopowerwordlength[a] == sum(2.0^(i)*wordlength_ai[a, i] for i in 1:max_wordlength))

        if max_output_error != 0
            @constraint(model, [a in 1:NA], twopowerwordlength[a] >= (2.0^(wordlength_in)-1)*(ca[a] + internal_pos_error[a]))
            @constraint(model, [a in 1:NA], twopowerwordlength[a] <= (2.0^(wordlength_in+1)-1)*(ca[a] + internal_pos_error[a]))
        else
            @constraint(model, [a in 1:NA], twopowerwordlength[a] >= (2.0^(wordlength_in)-1)*ca[a])
            @constraint(model, [a in 1:NA], twopowerwordlength[a] <= (2.0^(wordlength_in+1)-1)*ca[a])
        end

        @constraint(model, [a in 1:known_min_NA], onebit_a_used[a] == onebit_a[a])

        if minimize_adder_cost
            @variable(model, 0 <= max_oba <= max_wordlength, Int)
            @constraint(model, [a in 1:NA], max_oba >= onebit_a_used[a])
        end

        if minimize_one_bit_depth
            # Add oba depth
            @variable(model, 0 <= obada[0:NA] <= NA*max_wordlength)
            fix(obada[0], 0, force=true)
            @variable(model, 0 <= max_obad <= NA*max_wordlength, Int)
            @constraint(model, [a in 1:NA, i in 1:2, k in 0:(a-1)], obada[a] >= obada[k]+1 - (1-caik[a,i,k])*NA*max_wordlength)
            @constraint(model, [a in 1:NA], max_obad >= obada[a])
        end
    end

    if known_min_NA < NA
        @variable(model, used_adder[(known_min_NA+1):NA], Bin)
        if (known_min_NA+2) <= NA
            @constraint(model, [a in (known_min_NA+2):NA], used_adder[a] <= used_adder[a-1])
        end
        @constraint(model, [a in (known_min_NA+1):NA], ca[a] <= used_adder[a]*maximum_value + 1)
        if !with_pipelining_cost
            @constraint(model, [a in (known_min_NA+1):NA], ca[a] >= 3*used_adder[a])
        end
        @constraint(model, [a in (known_min_NA+1):NA, i in 1:2], caik[a,i,0] >= 1-used_adder[a])

        if wordlength_in > 0
            @constraint(model, [a in (known_min_NA+1):NA], onebit_a_used[a] <= onebit_a[a]+max_wordlength*(1-used_adder[a]))
            @constraint(model, [a in (known_min_NA+1):NA], onebit_a_used[a] >= onebit_a[a]-max_wordlength*(1-used_adder[a]))
            @constraint(model, [a in (known_min_NA+1):NA], onebit_a_used[a] <= max_wordlength*used_adder[a])
        end
    end

    # Last adder is equal to an output
    @constraint(model, ca[end] <= maximum(C))
    if known_min_NA == NA
        @constraint(model, ca[end] == sum(C[j]*oaj[end,j] for j in 1:NO))
    end
    if known_min_NA < NA
        @constraint(model, used_adder[end] == sum(oaj[end,j] for j in 1:NO))
        @constraint(model, ca[end] >= sum(C[j]*oaj[end,j] for j in 1:NO))
        @constraint(model, ca[end] <= sum(C[j]*oaj[end,j] for j in 1:NO) + (1-used_adder[end])*maximum_value)
    end
    # At least x adders should be equal to an output at adder n
    @constraint(model, [n in 1:NA], sum(oaj[a,j] for a in 1:n, j in 1:NO) >= NO - (NA-n))
    # Adders are outputs or used for following ones or not used
    @constraint(model, [a in 1:(known_min_NA-1)], sum(oaj[a,j] for j in 1:NO) +
        sum(caik[var_adder,i,a] for var_adder in (a+1):NA, i in 1:2) >= 1)
    if known_min_NA < NA
        @constraint(model, sum(oaj[known_min_NA,j] for j in 1:NO) +
            sum(caik[var_adder,i,known_min_NA] for var_adder in (known_min_NA+1):NA, i in 1:2) >= 1)
        @constraint(model, [a in (known_min_NA+1):(NA-1)], sum(oaj[a,j] for j in 1:NO) +
            sum(caik[var_adder,i,a] for var_adder in (a+1):NA, i in 1:2) >= used_adder[a])
    end

    if !with_pipelining_cost
        # no duplicate adder
        @variable(model, cadiff[a in 1:(NA-1), aprime in (a+1):NA], Bin)
        @constraint(model, [a in 1:(known_min_NA-1), aprime in (a+1):known_min_NA], ca[a] <= ca[aprime] - 1 + (maximum_value+1)*cadiff[a, aprime])
        @constraint(model, [a in 1:(known_min_NA-1), aprime in (a+1):known_min_NA], ca[a] >= ca[aprime] + 1 - (maximum_value+1)*(1 - cadiff[a, aprime]))
        if known_min_NA < NA
            @constraint(model, [a in 1:(NA-1), aprime in max(a+1, known_min_NA+1):NA], ca[a] <= ca[aprime] - 1 + (maximum_value+1)*cadiff[a, aprime] + (1-used_adder[aprime]))
            @constraint(model, [a in 1:(NA-1), aprime in max(a+1, known_min_NA+1):NA], ca[a] >= ca[aprime] + 1 - (maximum_value+1)*(1 - cadiff[a, aprime]) - (1-used_adder[aprime]))
        end
    end

    if with_pipelining_cost
        @variable(model, ca_used_at_ad[0:(NA-1), 1:NA], Bin)
        if known_min_NA < NA
            @constraint(model, [a in 1:known_min_NA, k in 0:(a-1)], ada[k] <= ada[a])
            @constraint(model, [a in (known_min_NA+1):NA, k in 0:(a-1)], ada[k] <= ada[a] + NA*used_adder[a])
            @constraint(model, [a in 0:(known_min_NA-1), i in 1:2, ad in 1:NA, k in (a+1):known_min_NA], NA*ca_used_at_ad[a, ad] >= ada[k]-ad+1 - (1-caik[k,i,a])*2*NA)
            @constraint(model, [a in 0:(NA-1), i in 1:2, ad in 1:NA, k in (max(a, known_min_NA)+1):NA], NA*ca_used_at_ad[a, ad] >= ada[k]-ad+1 - (1-caik[k,i,a])*2*NA - (1-used_adder[k])*2*NA)
        else
            @constraint(model, [a in 1:NA, k in 0:(a-1)], ada[k] <= ada[a])
            @constraint(model, [a in 0:(NA-1), i in 1:2, ad in 1:NA, k in (a+1):NA], NA*ca_used_at_ad[a, ad] >= ada[k]-ad+1 - (1-caik[k,i,a])*NA)
        end
        @variable(model, used_as_output[0:NA], Bin)
        @constraint(model, used_as_output[0] == one_is_output)
        @constraint(model, [a in 1:NA], NA*used_as_output[a] >= sum(oaj[a,j] for j in 1:NO))
        @variable(model, 0 <= max_ad_diff[0:NA] <= NA+1, Int) # diff between ad of c_a and max_ad_used
        @constraint(model, [a in 0:NA, ad in 1:NA], max_ad_diff[a] >= max_ad+1 - ada[a] - (1-used_as_output[a])*NA)
        @constraint(model, [a in 0:(NA-1), ad in 1:NA], max_ad_diff[a] >= ca_used_at_ad[a, ad]*ad - ada[a])
        @variable(model, nb_registers[0:NA] >= 0, Int)
        if wordlength_in > 0
            @variable(model, max_ad_diff_bin[0:NA, 0:(NA+1)], Bin)
            @constraint(model, [a in 0:NA], sum(ad*max_ad_diff_bin[a, ad] for ad in 0:(NA+1)) == max_ad_diff[a])
            @constraint(model, [a in 0:NA], sum(max_ad_diff_bin[a, ad] for ad in 0:(NA+1)) == 1)
            # @constraint(model, [a in 0:(NA-1), ad in 0:NA], ad*max_ad_diff_bin[a, ad] == max_ad_diff[a])
            @constraint(model, [ad in 1:(NA+1)], nb_registers[0] >= ad*wordlength_in - (1-max_ad_diff_bin[0, ad])*(NA*max_wordlength))
            # @constraint(model, [a in 1:NA, ad in 1:NA], nb_registers[a] >= (ad-1)*onebit_a_used[a] - (1-max_ad_diff_bin[a, ad])*(NA*max_wordlength))
            @constraint(model, [a in 1:NA, ad in 1:(NA+1)], nb_registers[a] >= ad*wordlength_a[a] - (1-max_ad_diff_bin[a, ad])*(NA*max_wordlength))
        else
            @constraint(model, [a in 0:NA], nb_registers[a] >= max_ad_diff[a])
        end
        if known_min_NA < NA
            if wordlength_in > 0
                @constraint(model, [a in (known_min_NA+1):NA], nb_registers[a] <= used_adder[a]*(NA+1)*max_wordlength)
            else
                @constraint(model, [a in (known_min_NA+1):NA], nb_registers[a] <= used_adder[a]*(NA+1))
            end
        end
        @variable(model, total_nb_registers >= 0, Int)
        @constraint(model, total_nb_registers == sum(nb_registers))
    end

    if wordlength_in > 0
        @expression(model, onebit_or_NA_obj, sum(onebit_a_used))
    else
        if known_min_NA < NA
            @expression(model, onebit_or_NA_obj, known_min_NA+sum(used_adder))
        else
            @expression(model, onebit_or_NA_obj, NA)
        end
    end
    if with_pipelining_cost
        @expression(model, pipeline_obj, adder_cost*onebit_or_NA_obj + register_cost*total_nb_registers)
    else
        @expression(model, pipeline_obj, onebit_or_NA_obj)
    end
    if minimize_adder_cost && wordlength_in != 0
        @expression(model, ad_obj, max_wordlength*pipeline_obj + max_oba)
    elseif minimize_one_bit_depth && wordlength_in != 0
        @expression(model, ad_obj, max_wordlength*NA*pipeline_obj + max_obad)
    elseif minimize_adder_depth
        @expression(model, ad_obj, NA*pipeline_obj + max_ad)
    else
        @expression(model, ad_obj, pipeline_obj)
    end
    @objective(model, Min, ad_obj)

    if use_warmstart
        if isempty(ws_values)
            fix(ca[0], 1, force=true)
            current_adder_depth_max_value = 0
            for a in 1:nb_var_warmstart
                curr_value = get_value(addernodes[a])
                # println("$(a): $(curr_value)")
                if curr_value > maximum_value
                    continue
                end
                left_input_value = get_input_addernode_values(addernodes[a])[1]
                right_input_value = get_input_addernode_values(addernodes[a])[2]
                depth_input_left = get_depth(addernodes[a]) - 1
                while get(addernodes_value_to_index, (left_input_value, depth_input_left), -1) == -1
                    depth_input_left -= 1
                    if depth_input_left == -1
                        break
                    end
                end
                depth_input_right = get_depth(addernodes[a]) - 1
                while get(addernodes_value_to_index, (right_input_value, depth_input_right), -1) == -1
                    depth_input_right -= 1
                    if depth_input_right == -1
                        break
                    end
                end
                # println("Left and right input found")
                left_input = addernodes_value_to_index[left_input_value, depth_input_left]
                right_input = addernodes_value_to_index[right_input_value, depth_input_right]
                # left_input_value = 1
                # if left_input != 0
                #     left_input_value = get_value(addernodes[left_input])
                # end
                # right_input_value = 1
                # if right_input != 0
                #     right_input_value = get_value(addernodes[right_input])
                # end
                left_shift, right_shift = get_input_shifts(addernodes[a])
                left_negative, right_negative = are_negative_inputs(addernodes[a])
                fix(ca[a], curr_value, force=true)
                fix(ca_no_shift[a], curr_value*(2^max(-right_shift, 0)), force=true)
                fix(force_odd[a], div(curr_value, 2), force=true)
                if left_input_value <= maximum_value-1 && right_input_value <= maximum_value-1
                    fix(cai[a, 1], left_input_value, force=true)
                    fix(cai[a, 2], right_input_value, force=true)
                    fix(cai_left_sh[a], left_input_value*(2^max(0, left_shift)), force=true)
                    if left_negative
                        fix(cai_left_shsg[a], -left_input_value*(2^max(0, left_shift)), force=true)
                    else
                        fix(cai_left_shsg[a], left_input_value*(2^max(0, left_shift)), force=true)
                    end
                    if right_negative
                        fix(cai_right_sg[a], -right_input_value, force=true)
                    else
                        fix(cai_right_sg[a], right_input_value, force=true)
                    end
                    for k in 0:(a-1)
                        fix(caik[a, 1, k], 0, force=true)
                        fix(caik[a, 2, k], 0, force=true)
                    end
                    fix(caik[a, 1, left_input], 1, force=true)
                    fix(caik[a, 2, right_input], 1, force=true)
                    fix(Phiai[a, 1], left_negative, force=true)
                    fix(Phiai[a, 2], right_negative, force=true)
                    fix.(Psias[a, :], 0, force=true)
                    fix.(phias[a, :], 0, force=true)
                    if right_shift >= Smin && right_shift <= 0
                        fix(Psias[a, right_shift], 1, force=true)
                    end
                    if left_shift >= 0 && left_shift <= Smax
                        fix(phias[a, left_shift], 1, force=true)
                    elseif left_shift < 0
                        fix(phias[a, 0], 1, force=true)
                    end
                    if minimize_adder_depth || adder_depth_max != 0
                        fix(ada[a], get_depth(addernodes[a]), force=true)
                        current_adder_depth_max_value = max(current_adder_depth_max_value, get_depth(addernodes[a]))
                    end
                end
                fix.(oaj[a, :], 0, force=true)
                if (curr_value in C) && (a == nb_var_warmstart || !(curr_value in get_value.(addernodes[(a+1):nb_var_warmstart])))
                    fix(oaj[a, findfirst(isequal(curr_value), C)], 1, force=true)
                    # println("Is used as output")
                end
            end
            if minimize_adder_depth || adder_depth_max != 0
                fix(max_ad, current_adder_depth_max_value, force=true)
            end

            if known_min_NA < NA
                for a in (nb_var_warmstart+1):NA
                    fix(used_adder[a], 0, force=true)
                    # fix(ca[a], 1, force=true)
                end
                for a in (known_min_NA+1):nb_var_warmstart
                    fix(used_adder[a], 1, force=true)
                end
            end

            optimize!(model)

            all_variable_names = sort!(name.(all_variables(model)))
            ws_values = Dict{String, Float64}()
            for varname in all_variable_names
                var_curr = variable_by_name(model, varname)
                var_val = value(var_curr)
                if is_integer(var_curr) || is_binary(var_curr)
                    var_val = round(var_val)
                end
                ws_values[varname] = var_val
            end
            empty!(model)

            return model_mcm_forumlation!(
                model, C, wordlength, NA;
                use_all_adders=use_all_adders,
                adder_depth_max=adder_depth_max,
                minimize_adder_depth=minimize_adder_depth,
                minimize_one_bit_depth=minimize_one_bit_depth,
                minimize_adder_cost=minimize_adder_cost,
                minimize_critical_path=minimize_critical_path,
                wordlength_in=wordlength_in,
                no_one_bit_adders=no_one_bit_adders,
                input_error=input_error,
                output_errors=output_errors,
                verbose=verbose,
                known_min_NA=known_min_NA,
                with_pipelining_cost=with_pipelining_cost,
                adder_cost=adder_cost,
                register_cost=register_cost,
                max_dsp=max_dsp,
                one_is_output=one_is_output,
                addergraph_warmstart=addergraph_warmstart,
                use_big_m=use_big_m,
                no_right_shifts=no_right_shifts,
                ws_values=ws_values,
                kwargs...
            )
        else
            all_variable_names = sort!(name.(all_variables(model)))
            for varname in all_variable_names
                set_start_value(variable_by_name(model, varname), ws_values[varname])
            end
        end
    end

    verbose && println("Model generated")

    return model
end




"""
    optimize_increment!(model::Model, 
                        C::Vector{Int}, wordlength::Int;
                        verbose::Bool)::Model

Increment NA until a solution is found for the coefficients in `C`.
"""
function optimize_increment!(model::Model,
                             C::Vector{Int}, wordlength::Int,
                             ;verbose::Bool = false, nb_adders_start::Int=1,
                             use_warmstart::Bool=true,
                             use_mcm_warmstart::Bool=true,
                             use_mcm_warmstart_time_limit_sec::Float64=0.0,
                             addergraph_warmstart::AdderGraph=AdderGraph(),
                             with_pipelining_cost::Bool=false, increase_NA::Int=2,
                             one_is_output::Bool=false,
                             # write_model::String="",
                             kwargs...
    )::Model
    Cplusone = copy(C)
    if one_is_output
        pushfirst!(Cplusone, 1)
    end
    if use_warmstart && isempty(addergraph_warmstart)
        addergraph_warmstart = rpag(Cplusone, with_register_cost=with_pipelining_cost)
        verbose && println("Warmstart adder graph rpag: $(write_addergraph(addergraph_warmstart))")
    end
    known_min_NA = get_min_number_of_adders(C)
    NA = max(known_min_NA, nb_adders_start)
    timelimit = time_limit_sec(model)
    total_solve_time = 0.0
    current_solve_time = 0.0
    if use_mcm_warmstart
        if use_mcm_warmstart_time_limit_sec == 0.0
            @warn "no use_mcm_warmstart_time_limit_sec value provided, default: 30seconds"
            use_mcm_warmstart_time_limit_sec = 30.0
        end
        set_time_limit_sec(model, use_mcm_warmstart_time_limit_sec)
        addergraph_warmstart = mcm(model, Cplusone;
            kwargs...,
            nb_adders_start=nb_adders_start, use_mcm_warmstart=false, addergraph_warmstart=addergraph_warmstart, verbose=verbose, 
            with_pipelining_cost=with_pipelining_cost, wordlength_in=0,
            minimize_adder_depth=false, minimize_adder_cost=false, minimize_critical_path=false, minimize_one_bit_depth=false,
            input_error=0, output_error=0, output_errors_dict=Dict{Int, Int}(), output_errors=Vector{Int}(),
        )
        NA = length(get_nodes(addergraph_warmstart))
        if termination_status(model) == MOI.OPTIMAL
            known_min_NA = NA#round(Int, objective_value(model; result=1))
        end
        current_solve_time = use_mcm_warmstart_time_limit_sec - time_limit_sec(model) + solve_time(model)
        total_solve_time += current_solve_time
        verbose && println("Warmstart adder graph: $(write_addergraph(addergraph_warmstart))")
        verbose && println("NA after warmstart: $(NA)")
    end
    if with_pipelining_cost
        NA = NA+increase_NA
    end
    while true
        if !isnothing(timelimit)
            timelimit -= current_solve_time
            if timelimit <= 0.0
                break
            end
        end
        empty!(model)
        model_mcm_forumlation!(model, C, wordlength, NA; addergraph_warmstart=addergraph_warmstart, one_is_output=one_is_output, verbose=verbose, known_min_NA=known_min_NA, with_pipelining_cost=with_pipelining_cost, kwargs...)
        if !isnothing(timelimit)
            set_time_limit_sec(model, timelimit)
        end
        optimize!(model)
        current_solve_time = solve_time(model)
        total_solve_time += current_solve_time
        verbose && println("$(termination_status(model)) for NAmax = $(NA), bestNA=$(has_values(model) ? (sum(round(value(model[:ca][a])) != 1 ? 1 : 0 for a in 1:NA)) : "X") in $(current_solve_time) seconds")
        NA += 1
        known_min_NA = NA
        (termination_status(model) in [MOI.INFEASIBLE, MOI.INFEASIBLE_OR_UNBOUNDED]) || break
    end
    NA -= 1
    model[:NA] = Vector{Int}()
    count_solution = 0
    while has_values(model; result=count_solution+1)
        count_solution += 1
        push!(model[:NA], sum(round(value(model[:ca][a]; result=count_solution)) != 1 ? 1 : 0 for a in 1:NA))
    end
    if !isempty(model[:NA])
        NA = model[:NA][1]
    end
    model[:total_solve_time] = total_solve_time
    verbose && println("Total time: $total_solve_time seconds\n\n\n")

    return model
end
