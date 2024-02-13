using Statistics
using AdderGraphs

function generate_vhdl_all()
    nb_files_per_folder = 10
    wordlength_in = 8
    all_ag_files = readdir("$(@__DIR__)/addergraphs")
    nb_folders = round(Int, length(all_ag_files)/nb_files_per_folder, RoundUp)
    for i in 1:nb_folders
        mkdir("$(@__DIR__)/vhdl/vhdl$(i)")
        for agfile in all_ag_files[(nb_files_per_folder*(i-1))+1:min(nb_files_per_folder*i,length(all_ag_files))]
            open("$(@__DIR__)/addergraphs/$(agfile)", "r") do readag
                lines = readlines(readag)
                println("$i -- $agfile")
                ag = read_addergraph(lines[1][8:(end-1)])
                write_vhdl(ag, wordlength_in=wordlength_in, vhdl_filename="$(@__DIR__)/vhdl/vhdl$(i)/$(agfile[1:(end-4)])_ag.vhdl", pipeline_inout=true)
                write_vhdl(ag, wordlength_in=wordlength_in, vhdl_filename="$(@__DIR__)/vhdl/vhdl$(i)/$(agfile[1:(end-4)])_luts.vhdl", no_addergraph=true, use_tables=true, pipeline_inout=true)
                write_vhdl(ag, wordlength_in=wordlength_in, vhdl_filename="$(@__DIR__)/vhdl/vhdl$(i)/$(agfile[1:(end-4)])_prod.vhdl", no_addergraph=true, pipeline_inout=true)
                write_vhdl(ag, wordlength_in=wordlength_in, vhdl_filename="$(@__DIR__)/vhdl/vhdl$(i)/$(agfile[1:(end-4)])_force_dsp.vhdl", no_addergraph=true, force_dsp=true, pipeline_inout=true)
            end
        end
    end

    return nothing
end


function generate_vhdl()
    nb_files_per_folder = 40
    wordlength_in = 8
    #all_ag_files = filter!(x -> occursin("pmcm", x), readdir("$(@__DIR__)/addergraphs"))
    all_ag_files = readdir("$(@__DIR__)/addergraphs")
    nb_folders = round(Int, length(all_ag_files)/nb_files_per_folder, RoundUp)
    for i in 1:nb_folders
        mkdir("$(@__DIR__)/vhdl/vhdl$(i)")
        for agfile in all_ag_files[(nb_files_per_folder*(i-1))+1:min(nb_files_per_folder*i,length(all_ag_files))]
            open("$(@__DIR__)/addergraphs/$(agfile)", "r") do readag
                lines = readlines(readag)
                println("$i -- $agfile")
                ag = read_addergraph(lines[1][8:(end-1)])
                write_vhdl(ag, wordlength_in=wordlength_in, vhdl_filename="$(@__DIR__)/vhdl/vhdl$(i)/$(agfile[1:(end-4)])_$(get_adder_depth(ag)).vhdl", pipeline=true, pipeline_inout=true)
            end
        end
    end

    return nothing
end


function generate_vivado_calls()
    all_vhdlfoders = readdir("$(@__DIR__)/vhdl")
    for current_folder in all_vhdlfoders
        mkdir("$(@__DIR__)/vhdl/$(current_folder)/vhdl")
        mkdir("$(@__DIR__)/vhdl/$(current_folder)/dot")
        cp("$(@__DIR__)/synthesis_vivado.sh", "$(@__DIR__)/vhdl/$(current_folder)/synthesis.sh")
        open("$(@__DIR__)/vhdl/$(current_folder)/fvcalls.txt", "w") do writefile
            all_files = filter!(x -> occursin(".vhdl", x), readdir("$(@__DIR__)/vhdl/$(current_folder)"))
            for current_file in all_files
                write(writefile,
                    "python \$SOFTWARE_FOLDER/flopoco/tools/vivado-runsyn.py --implement --vhdl $(current_file)\n"
                )
            end
        end
    end

    return nothing
end

function generate_flopocovivado_calls()
    nb_files_per_folder = 30
    all_ag_files = readdir("$(@__DIR__)/addergraphs")
    nb_folders = round(Int, length(all_ag_files)/nb_files_per_folder, RoundUp)
    for i in 1:nb_folders
        mkdir("$(@__DIR__)/vhdl/vhdl$i")
        mkdir("$(@__DIR__)/vhdl/vhdl$i/vhdl")
        mkdir("$(@__DIR__)/vhdl/vhdl$i/dot")
        cp("$(@__DIR__)/synthesis.sh", "$(@__DIR__)/vhdl/vhdl$i/synthesis.sh")
        open("$(@__DIR__)/vhdl/vhdl$i/fvcalls.txt", "w") do writefile
            for agfile in all_ag_files[(nb_files_per_folder*(i-1))+1:min(nb_files_per_folder*i,length(all_ag_files))]
                open("$(@__DIR__)/addergraphs/$(agfile)", "r") do readag
                    lines = readlines(readag)
                    println("$i -- $agfile")
                    ag = lines[1]
                    trunc = lines[2]
                    write(writefile,
                        "flopoco IntConstMultShiftAdd wIn=8 $(ag) $(trunc) outputFile=$(agfile[1:(end-4)]).vhdl Wrapper\n"
                    )
                    write(writefile,
                        "python \$SOFTWARE_FOLDER/flopoco/tools/vivado-runsyn.py --implement --vhdl $(agfile[1:(end-4)]).vhdl\n"
                    )
                end
            end
        end
        # flopoco useTargetOptimizations=1 IntMultiplier wX=64 wY=64 useDSP=false use2xk=true maxDSP=0
    end

    return nothing
end


function merge_hw_results()
    all_hw_folders = filter!(x -> occursin("vhdl", x), readdir("$(@__DIR__)/vhdl"))
    nb_folders = length(all_hw_folders)
    cp("$(@__DIR__)/vhdl/vhdl1/vivadoSynResults.csv", "$(@__DIR__)/vhdl/results_hw.csv")
    open("$(@__DIR__)/vhdl/results_hw.csv", "a") do writefile
        for i in 2:nb_folders
            open("$(@__DIR__)/vhdl/vhdl$i/vivadoSynResults.csv", "r") do readfile
                lines = readlines(readfile)
                for line in lines[2:end]
                    write(writefile, line)
                    write(writefile, "\n")
                end
            end
        end
    end

    return nothing
end


function merge_results_csv()
    hw_results = Dict{String, String}()
    opt_results = Dict{String, String}()
    open("$(@__DIR__)/results_hw.csv", "r") do readfile
        lines = readlines(readfile)
        for line in lines[2:end]
            instance_name = split(strip(split(line, ";")[1]), ".")[1]
            if haskey(hw_results, instance_name)
                println("hw results, duplicate: $instance_name")
            end
            current_hw_result_data = strip.(split(line, ","))
            current_hw_result = "$(current_hw_result_data[2]), $(current_hw_result_data[4]), $(isempty(current_hw_result_data[10]) ? "" : round(Int, 1000*((current_hw_result_data[7] == "<0.001" ? 0.001 : parse(Float64, current_hw_result_data[7]))+(current_hw_result_data[9] == "<0.001" ? 0.001 : parse(Float64, current_hw_result_data[9]))+(current_hw_result_data[10] == "<0.001" ? 0.001 : parse(Float64, current_hw_result_data[10])))))"
            hw_results[instance_name] = current_hw_result
        end
    end
    open("$(@__DIR__)/results.csv", "r") do readfile
        lines = readlines(readfile)
        for line in lines[2:end]
            instance_name = split(strip(split(line, ",")[2]), ".")[1]
            if haskey(opt_results, instance_name)
                println("opt results, duplicate: $instance_name")
            end
            current_opt_result = strip(join(split(line, ",")[2:end], ","))
            opt_results[instance_name] = current_opt_result
        end
    end

    open("$(@__DIR__)/results_all.csv", "a") do writefile
        write(writefile, "name, file_ag,method,min_ad,time,NA,ad,wl_in,onebit,epsilon_max,wl_out_full,wl_out,epsilon_frac,luts,delay,power\n")
        instance_names = keys(opt_results)
        for instance_name in instance_names
            write(writefile, split(split(instance_name, "_mcm")[1], "_tmcm")[1])
            write(writefile, ", ")
            write(writefile, opt_results[instance_name])
            write(writefile, ", ")
            write(writefile, get(hw_results, instance_name, ""))
            write(writefile, "\n")
        end
    end

    return nothing
end


function results_to_table()
    table_str = """
\\begin{table*}[]
	\\centering
	\\caption{Delay (ns), Power (mW)}\\label{tab:allresults}
	{\\small
	\\setlength{\\tabcolsep}{4pt}
	\\begin{tabular}{@{}ccccccc|cccccc|cccccc@{}}
		\\toprule
		\\multirow{2}{*}{Bench} & \\multicolumn{6}{c}{\\MCMA} & \\multicolumn{6}{c}{\\MCMB} & \\multicolumn{6}{c}{\\TMCM} \\\\
		\\cmidrule(lr){2-7} \\cmidrule(lr){8-13} \\cmidrule(lr){14-19}
		& \$N_A\$ & \$\\AD\$ & \\#B & \\#LUTs & Delay & Power & \$N_A\$ & \$\\AD\$ & \\#B & \\#LUTs & Delay & Power & \$N_A\$ & \$\\AD\$ & \\#B & \\#LUTs & Delay & Power \\\\ \\midrule
"""
    NAadBldpmcma = Dict{String, Tuple{String, String, String, String, String, String}}()
    NAadBldpmcmb = Dict{String, Tuple{String, String, String, String, String, String}}()
    NAadBldptmcm = Dict{String, Tuple{String, String, String, String, String, String}}()
    instance_names = Vector{String}()
    open("$(@__DIR__)/results_all.csv", "r") do readfile
        lines = readlines(readfile)
        for line in lines[2:end]
            # name	file_ag	method	min_ad	time	NA	ad	wl_in	onebit	epsilon_max	wl_out_full	wl_out	epsilon_frac	LUTs, Delay, Power
            data_str = split(line, ",")
            while length(data_str) < 16
                push!(data_str, "")
            end
            instance_name_init, _, method, min_ad_str, _, NA_str, AD_str, _, onebit_str, _, _, _, epsilon_frac_str, luts_str, delay_str, power_str = strip.(data_str)
            if !(instance_name_init in ["GAUSSIAN_3", "GAUSSIAN_5", "HIGHPASS_5", "HIGHPASS_9", "HIGHPASS_15", "LOWPASS_5", "LOWPASS_9", "LOWPASS_15", "UNSHARP_3-1", "UNSHARP_3-2", "LAPLACIAN_3"])
                continue
            end
            instance_name_init = instance_name_init[1]*(occursin("PASS", instance_name_init) ? "P" : ".")*instance_name_init[findfirst("_", instance_name_init)[1]:end]
            instance_name = replace(instance_name_init, "_" => "")
            min_ad = parse(Bool, min_ad_str)
            epsilon_frac = parse(Int, split(epsilon_frac_str, "/")[2])
            push!(instance_names, instance_name)
            if method == "mcm" && !min_ad
                NAadBldpmcma[instance_name] = (NA_str, AD_str, onebit_str, luts_str, delay_str, power_str)
            elseif method == "mcmb"
                NAadBldpmcmb[instance_name] = (NA_str, AD_str, onebit_str, luts_str, delay_str, power_str)
            elseif method == "tmcm" && epsilon_frac == 1
                NAadBldptmcm[instance_name] = (NA_str, AD_str, onebit_str, luts_str, delay_str, power_str)
            end
        end
    end
    unique!(instance_names)
    instance_name_to_delete = falses(length(instance_names))
    for i in 1:length(instance_names)
        instance_name = instance_names[i]
        if !(haskey(NAadBldpmcma, instance_name)) || !(haskey(NAadBldpmcmb, instance_name)) || !(haskey(NAadBldptmcm, instance_name))
            instance_name_to_delete[i] = true
        end
    end
    deleteat!(instance_names, instance_name_to_delete)
    for instance_name in instance_names
        NAmcma, ADmcma, Bmcma, Lmcma, Dmcma, Pmcma = get(NAadBldpmcma, instance_name, ("","","","","",""))
        NAmcmb, ADmcmb, Bmcmb, Lmcmb, Dmcmb, Pmcmb = get(NAadBldpmcmb, instance_name, ("","","","","",""))
        NAtmcm, ADtmcm, Btmcm, Ltmcm, Dtmcm, Ptmcm = get(NAadBldptmcm, instance_name, ("","","","","",""))
        table_str *= "\\multicolumn{1}{l|}{\\texttt{$(replace(instance_name, "_" => "\\_"))}} & "
        table_str *= "$(NAmcma) & $(ADmcma) & $(Bmcma) & $(Lmcma) & $(Dmcma[1:(end-2)]) & $(Pmcma) & "
        table_str *= "$(NAmcmb) & $(ADmcmb) & $(Bmcmb) & $(Lmcmb) & $(Dmcmb[1:(end-2)]) & $(Pmcmb) & "
        table_str *= "$(NAtmcm) & $(ADtmcm) & $(Btmcm) & $(Ltmcm) & $(Dtmcm[1:(end-2)]) & $(Ptmcm) \\\\\n"
    end

    table_str *= """
    \\bottomrule
    \\end{tabular}
    }
\\end{table*}
"""
    open("$(@__DIR__)/tex/results_table.tex", "w") do writefile
        write(writefile, table_str)
    end
    return nothing
end


function results_to_correlation()
    NAmcma = Vector{Int}()
    NAmcmad = Vector{Int}()
    NAmcmb = Vector{Int}()
    NAtmcm = Vector{Int}()
    ADmcma = Vector{Int}()
    ADmcmad = Vector{Int}()
    ADmcmb = Vector{Int}()
    ADtmcm = Vector{Int}()
    Bmcma = Vector{Int}()
    Bmcmad = Vector{Int}()
    Bmcmb = Vector{Int}()
    Btmcm = Vector{Int}()
    Lmcma = Vector{Int}()
    Lmcmad = Vector{Int}()
    Lmcmb = Vector{Int}()
    Ltmcm = Vector{Int}()
    Dmcma = Vector{Float64}()
    Dmcmad = Vector{Float64}()
    Dmcmb = Vector{Float64}()
    Dtmcm = Vector{Float64}()
    Pmcma = Vector{Int}()
    Pmcmad = Vector{Int}()
    Pmcmb = Vector{Int}()
    Ptmcm = Vector{Int}()
    instance_names = Vector{String}()
    ADmcma_dict = Dict{String, Int}()
    ADmcmad_dict = Dict{String, Int}()
    ADmcmb_dict = Dict{String, Int}()
    ADtmcm_dict = Dict{String, Int}()
    Dmcma_dict = Dict{String, Float64}()
    Dmcmad_dict = Dict{String, Float64}()
    Dmcmb_dict = Dict{String, Float64}()
    Dtmcm_dict = Dict{String, Float64}()
    open("$(@__DIR__)/results_all.csv", "r") do readfile
        lines = readlines(readfile)
        for line in lines[2:end]
            # name	file_ag	method	min_ad	time	NA	ad	wl_in	onebit	epsilon_max	wl_out_full	wl_out	epsilon_frac	LUTs, Delay, Power
            data_str = split(line, ",")
            while length(data_str) < 16
                push!(data_str, "")
            end
            instance_name_init, _, method, min_ad_str, _, NA_str, ad_str, _, onebit_str, _, _, _, epsilon_frac_str, luts_str, delay_str, power_str = strip.(data_str)
            instance_name = replace(instance_name_init, "_" => "\\_")
            push!(instance_names, instance_name)
            min_ad = parse(Bool, min_ad_str)
            epsilon_frac = parse(Int, split(epsilon_frac_str, "/")[2])
            if !isempty(onebit_str) && !isempty(luts_str)
                if method == "mcm" && !min_ad
                    push!(NAmcma, parse(Int, NA_str))
                    push!(ADmcma, parse(Int, ad_str))
                    push!(Bmcma, parse(Int, onebit_str))
                    push!(Lmcma, parse(Int, luts_str))
                    push!(Dmcma, parse(Float64, delay_str[1:(end-2)]))
                    push!(Pmcma, round(Int, 1000*parse(Float64, power_str)))
                    ADmcma_dict[instance_name] = parse(Int, ad_str)
                    Dmcma_dict[instance_name] = parse(Float64, delay_str[1:(end-2)])
                elseif method == "mcm" && min_ad
                    push!(NAmcmad, parse(Int, NA_str))
                    push!(ADmcmad, parse(Int, ad_str))
                    push!(Bmcmad, parse(Int, onebit_str))
                    push!(Lmcmad, parse(Int, luts_str))
                    push!(Dmcmad, parse(Float64, delay_str[1:(end-2)]))
                    push!(Pmcmad, round(Int, 1000*parse(Float64, power_str)))
                    ADmcmad_dict[instance_name] = parse(Int, ad_str)
                    Dmcmad_dict[instance_name] = parse(Float64, delay_str[1:(end-2)])
                elseif method == "mcmb"
                    push!(NAmcmb, parse(Int, NA_str))
                    push!(ADmcmb, parse(Int, ad_str))
                    push!(Bmcmb, parse(Int, onebit_str))
                    push!(Lmcmb, parse(Int, luts_str))
                    push!(Dmcmb, parse(Float64, delay_str[1:(end-2)]))
                    push!(Pmcmb, round(Int, 1000*parse(Float64, power_str)))
                    ADmcmb_dict[instance_name] = parse(Int, ad_str)
                    Dmcmb_dict[instance_name] = parse(Float64, delay_str[1:(end-2)])
                elseif method == "tmcm" && epsilon_frac == 1
                    push!(NAtmcm, parse(Int, NA_str))
                    push!(ADtmcm, parse(Int, ad_str))
                    push!(Btmcm, parse(Int, onebit_str))
                    push!(Ltmcm, parse(Int, luts_str))
                    push!(Dtmcm, parse(Float64, delay_str[1:(end-2)]))
                    push!(Ptmcm, round(Int, 1000*parse(Float64, power_str)))
                    ADtmcm_dict[instance_name] = parse(Int, ad_str)
                    Dtmcm_dict[instance_name] = parse(Float64, delay_str[1:(end-2)])
                end
            end
        end
    end
    unique!(instance_names)
    instance_name_to_delete = falses(length(instance_names))
    for i in 1:length(instance_names)
        instance_name = instance_names[i]
        if !(haskey(ADmcmb_dict, instance_name)) || !(haskey(ADmcmad_dict, instance_name)) || !(haskey(ADtmcm_dict, instance_name)) || !(haskey(ADmcma_dict, instance_name))
            instance_name_to_delete[i] = true
        end
    end
    deleteat!(instance_names, instance_name_to_delete)

    figure_str = """
\\begin{figure}
\\small
\\begin{tikzpicture}
\\begin{axis}[
    xlabel={\\#One-bit adders},
    ylabel={\\#LUTs},
    legend pos=south east,
    xmajorgrids=true,
    ymajorgrids=true,
]
"""
    figure_str *= """
\\addplot[color=mcma, fill=white, legend entry=\\MCMA, only marks, mark=*]
    coordinates {
"""
    for i in 1:length(Bmcma)
        figure_str *= "($(Bmcma[i]),$(Lmcma[i]))"
    end
    figure_str *= """
    };
"""
    figure_str *= """
\\addplot[color=mcmad, legend entry=\\MCMad, only marks, mark=x]
    coordinates {
"""
    for i in 1:length(Bmcmad)
        figure_str *= "($(Bmcmad[i]),$(Lmcmad[i]))"
    end
    figure_str *= """
};
"""
    figure_str *= """
\\addplot[color=mcmb, legend entry=\\MCMB, only marks, mark=square]
    coordinates {
"""
    for i in 1:length(Bmcmb)
        figure_str *= "($(Bmcmb[i]),$(Lmcmb[i]))"
    end
    figure_str *= """
};
"""
    figure_str *= """
\\addplot[color=tmcm, legend entry=\\TMCM, only marks, mark=+]
    coordinates {
"""
    for i in 1:length(Btmcm)
        figure_str *= "($(Btmcm[i]),$(Ltmcm[i]))"
    end
    figure_str *= """
};
"""

    figure_str *= """
    \\end{axis}
    \\end{tikzpicture}
    \\caption{Correlation \$r = $(cor([Bmcma; Bmcmad; Bmcmb; Btmcm], [Lmcma; Lmcmad; Lmcmb; Ltmcm]))\$}\\label{fig:correlationBLuts}
    %Correlation delay \$r = $(cor([Bmcma; Bmcmad; Bmcmb; Btmcm], [Dmcma; Dmcmad; Dmcmb; Dtmcm]))\$
    %Correlation power \$r = $(cor([Bmcma; Bmcmad; Bmcmb; Btmcm], [Pmcma; Pmcmad; Pmcmb; Ptmcm]))\$
    %Correlation NA/LUTS \$r = $(cor([NAmcma; NAmcmad; NAmcmb; NAtmcm], [Lmcma; Lmcmad; Lmcmb; Ltmcm]))\$
    %Correlation NA/delay \$r = $(cor([NAmcma; NAmcmad; NAmcmb; NAtmcm], [Dmcma; Dmcmad; Dmcmb; Dtmcm]))\$
    %Correlation NA/power \$r = $(cor([NAmcma; NAmcmad; NAmcmb; NAtmcm], [Pmcma; Pmcmad; Pmcmb; Ptmcm]))\$
    %Correlation AD/delay \$r = $(cor([ADmcma; ADmcmad; ADmcmb; ADtmcm], [Dmcma; Dmcmad; Dmcmb; Dtmcm]))\$
\\end{figure}\n\n\n
"""
    #
    figure_str *= """
\\begin{figure}
\\small
\\begin{tikzpicture}
\\begin{axis}[
    xlabel={AD},
    ylabel={Delay, ns},
    legend pos=south east,
    xmajorgrids=true,
    ymajorgrids=true,
]
"""
    figure_str *= """
\\addplot[color=mcma, fill=white, legend entry=\\MCMA, only marks, mark=*]
    coordinates {
"""
    for i in 1:length(Bmcma)
        figure_str *= "($(ADmcma[i]),$(Dmcma[i]))"
    end
    figure_str *= """
    };
"""
    figure_str *= """
\\addplot[color=mcmad, legend entry=\\MCMad, only marks, mark=x]
    coordinates {
"""
    for i in 1:length(Bmcmad)
        figure_str *= "($(ADmcmad[i]),$(Dmcmad[i]))"
    end
    figure_str *= """
};
"""
    figure_str *= """
\\addplot[color=mcmb, legend entry=\\MCMB, only marks, mark=square]
    coordinates {
"""
    for i in 1:length(Bmcmb)
        figure_str *= "($(ADmcmb[i]),$(Dmcmb[i]))"
    end
    figure_str *= """
};
"""
    figure_str *= """
\\addplot[color=tmcm, legend entry=\\TMCM, only marks, mark=+]
    coordinates {
"""
    for i in 1:length(Btmcm)
        figure_str *= "($(ADtmcm[i]),$(Dtmcm[i]))"
    end
    figure_str *= """
};
"""

    list_cor = Vector{Float64}()
    for instance_name in instance_names
        push!(list_cor, cor(
            [ADmcma_dict[instance_name], ADmcmad_dict[instance_name], ADmcmb_dict[instance_name], ADtmcm_dict[instance_name]],
            [Dmcma_dict[instance_name], Dmcmad_dict[instance_name], Dmcmb_dict[instance_name], Dtmcm_dict[instance_name]]
        ))
        if isnan(list_cor[end])
            pop!(list_cor)
        end
    end

    figure_str *= """
    \\end{axis}
    \\end{tikzpicture}
    \\caption{Correlation AD/delay \$r = $(cor([ADmcma; ADmcmad; ADmcmb; ADtmcm], [Dmcma; Dmcmad; Dmcmb; Dtmcm]))\$}\\label{fig:correlationADDelay}
    %Average correlation per instance: \$r = $(mean(list_cor))\$ on $(length(list_cor)) instances
\\end{figure}
"""

    open("$(@__DIR__)/tex/results_correlation.tex", "w") do writefile
        write(writefile, figure_str)
    end

    table_str = """
\\begin{table}[]
\\centering
\\caption{Correlation between different metrics and actual hardware cost}\\label{tab:correlation}
{\\small
	\\begin{tabular}{@{}c|ccc@{}}
		%\\toprule
		& \\#adders & \\#one-bit adders & adder depth \\\\
        \\midrule
"""
    #
    cor_precision = 10000
    table_str *= """
        \\#LUTs & \$$(round(cor_precision*cor([NAmcma; NAmcmad; NAmcmb; NAtmcm], [Lmcma; Lmcmad; Lmcmb; Ltmcm]))/cor_precision)\$ & \$$(round(cor_precision*cor([Bmcma; Bmcmad; Bmcmb; Btmcm], [Lmcma; Lmcmad; Lmcmb; Ltmcm]))/cor_precision)\$ & \$$(round(cor_precision*cor([ADmcma; ADmcmad; ADmcmb; ADtmcm], [Lmcma; Lmcmad; Lmcmb; Ltmcm]))/cor_precision)\$ \\\\
        Delay & \$$(round(cor_precision*cor([NAmcma; NAmcmad; NAmcmb; NAtmcm], [Dmcma; Dmcmad; Dmcmb; Dtmcm]))/cor_precision)\$ & \$$(round(cor_precision*cor([Bmcma; Bmcmad; Bmcmb; Btmcm], [Dmcma; Dmcmad; Dmcmb; Dtmcm]))/cor_precision)\$ & \$$(round(cor_precision*cor([ADmcma; ADmcmad; ADmcmb; ADtmcm], [Dmcma; Dmcmad; Dmcmb; Dtmcm]))/cor_precision)\$ \\\\
        Power & \$$(round(cor_precision*cor([NAmcma; NAmcmad; NAmcmb; NAtmcm], [Pmcma; Pmcmad; Pmcmb; Ptmcm]))/cor_precision)\$ & \$$(round(cor_precision*cor([Bmcma; Bmcmad; Bmcmb; Btmcm], [Pmcma; Pmcmad; Pmcmb; Ptmcm]))/cor_precision)\$ & \$$(round(cor_precision*cor([ADmcma; ADmcmad; ADmcmb; ADtmcm], [Pmcma; Pmcmad; Pmcmb; Ptmcm]))/cor_precision)\$ \\\\
"""
    #

    table_str *= """
		%\\bottomrule
	\\end{tabular}
}
\\end{table}
"""

    open("$(@__DIR__)/tex/results_correlation_table.tex", "w") do writefile
        write(writefile, table_str)
    end

    return nothing
end


function results_to_ad()
    ADmcma = Vector{Int}()
    ADmcmad = Vector{Int}()
    open("$(@__DIR__)/results_all.csv", "r") do readfile
        lines = readlines(readfile)
        for line in lines[2:end]
            # name	file_ag	method	min_ad	time	NA	ad	wl_in	onebit	epsilon_max	wl_out_full	wl_out	epsilon_frac	LUTs, Delay, Power
            data_str = split(line, ",")
            while length(data_str) < 16
                push!(data_str, "")
            end
            _, _, method, min_ad_str, _, _, ad_str, _, _, _, _, _, _, _, _, _ = strip.(data_str)
            min_ad = parse(Bool, min_ad_str)
            if method == "mcm" && !min_ad
                push!(ADmcma, parse(Int, ad_str))
            elseif method == "mcm" && min_ad
                push!(ADmcmad, parse(Int, ad_str))
            end
        end
    end
    admax = max(maximum(ADmcma), maximum(ADmcmad))
    nbminadmcma = zeros(Int, admax)
    nbminadmcmad = zeros(Int, admax)
    for ad in ADmcma
        nbminadmcma[ad] += 1
    end
    for ad in ADmcmad
        nbminadmcmad[ad] += 1
    end
    for i in 1:(admax-1)
        nbminadmcma[i+1] += nbminadmcma[i]
        nbminadmcmad[i+1] += nbminadmcmad[i]
    end
    figure_str = """
\\def\\varwidth{0.95\\linewidth}
\\def\\varheight{6cm}
\\begin{figure}
\\centering
\\begin{tikzpicture}
	\\begin{axis}[
	ybar,
	bar width=0.15,
	legend style={at={(0.5,-0.3)}, anchor=north, legend columns=2, font=\\small},
	legend cell align={left},
	ymin=0,
    ymajorgrids=true,
	ytick pos=left,
	xtick pos=bottom,
	width=\\varwidth,
	height=\\varheight,
	ylabel={\\#Adder graphs},
	xlabel={AD},
"""
    figure_str *= "xtick={1"
    for i in 2:admax
        figure_str *= ", $i"
    end
    figure_str *= "},\n"
    figure_str *= "xticklabels={\$=1\$"
    for i in 2:admax
        figure_str *= ", \$\\leq $i\$"
    end
    figure_str *= "},\n"

    figure_str *= """
	point meta=explicit symbolic
	]
	\\addplot [white, only marks, draw opacity=0, fill opacity=0] coordinates {(1, 1) (2, 1) (3, 1) (4, 1) (5, 1)};
"""
    figure_str *= "\\addplot[legend entry=\\MCMA, mcma, fill=mcmafill] coordinates {"
    for i in 1:admax
        figure_str *= "($i,$(nbminadmcma[i]))"
    end
    figure_str *= "};\n"
    figure_str *= "\\addplot[legend entry=\\MCMad, mcmad, fill=mcmadfill] coordinates {"
    for i in 1:admax
        figure_str *= "($i,$(nbminadmcmad[i]))"
    end
    figure_str *= "};\n"
    figure_str *= """
	\\end{axis}
\\end{tikzpicture}
\\caption{Adder depth comparison}\\label{fig:adderdepthcomparison}
\\end{figure}
"""

    open("$(@__DIR__)/tex/results_ad.tex", "w") do writefile
        write(writefile, figure_str)
    end
    return nothing
end


function results_to_bars()
    Bmcmb = Dict{String, Int}()
    Btmcm2 = Dict{String, Int}()
    Btmcm4 = Dict{String, Int}()
    Lmcmb = Dict{String, Int}()
    Ltmcm2 = Dict{String, Int}()
    Ltmcm4 = Dict{String, Int}()
    Dmcmb = Dict{String, Float64}()
    Dtmcm2 = Dict{String, Float64}()
    Dtmcm4 = Dict{String, Float64}()
    Pmcmb = Dict{String, Int}()
    Ptmcm2 = Dict{String, Int}()
    Ptmcm4 = Dict{String, Int}()
    instance_names = Vector{String}()
    open("$(@__DIR__)/results_all.csv", "r") do readfile
        lines = readlines(readfile)
        for line in lines[2:end]
            # name	file_ag	method	min_ad	time	NA	ad	wl_in	onebit	epsilon_max	wl_out_full	wl_out	epsilon_frac	LUTs, Delay, Power
            data_str = split(line, ",")
            while length(data_str) < 16
                push!(data_str, "")
            end
            instance_name_init, _, method, _, _, _, _, _, onebit_str, _, _, _, epsilon_frac_str, luts_str, delay_str, power_str = strip.(data_str)
            instance_name = replace(instance_name_init, "_" => "\\_")
            epsilon_frac = parse(Int, split(epsilon_frac_str, "/")[2])
            push!(instance_names, instance_name)
            if !isempty(onebit_str) && !isempty(luts_str)
                if method == "mcmb"
                    Bmcmb[instance_name] = parse(Int, onebit_str)
                    Lmcmb[instance_name] = parse(Int, luts_str)
                    Dmcmb[instance_name] = parse(Float64, delay_str[1:(end-2)])
                    Pmcmb[instance_name] = round(Int, 1000*parse(Float64, power_str))
                elseif method == "tmcm" && epsilon_frac == 2
                    Btmcm2[instance_name] = parse(Int, onebit_str)
                    Ltmcm2[instance_name] = parse(Int, luts_str)
                    Dtmcm2[instance_name] = parse(Float64, delay_str[1:(end-2)])
                    Ptmcm2[instance_name] = round(Int, 1000*parse(Float64, power_str))
                elseif method == "tmcm" && epsilon_frac == 4
                    Btmcm4[instance_name] = parse(Int, onebit_str)
                    Ltmcm4[instance_name] = parse(Int, luts_str)
                    Dtmcm4[instance_name] = parse(Float64, delay_str[1:(end-2)])
                    Ptmcm4[instance_name] = round(Int, 1000*parse(Float64, power_str))
                end
            end
        end
    end
    unique!(instance_names)
    instance_name_to_delete = falses(length(instance_names))
    for i in 1:length(instance_names)
        instance_name = instance_names[i]
        if !(haskey(Bmcmb, instance_name)) || !(haskey(Btmcm2, instance_name)) || !(haskey(Btmcm4, instance_name))
            instance_name_to_delete[i] = true
        end
    end
    deleteat!(instance_names, instance_name_to_delete)
    figure_str = """
\\begin{figure}
\\begin{tikzpicture}[
  every axis/.style={ % add these settings to all the axis environments in the tikzpicture
    ybar stacked,
    ymin=0,ymax=1.2,
    x tick label style={rotate=45,anchor=east},
    symbolic x coords={
        $(instance_names[1])"""
    for instance_name in instance_names[2:end]
        figure_str *= ",\n$(instance_name)"
    end
    figure_str *= """
    },
  bar width=8pt
  },
]
"""

    #LUTS
    figure_str *= """
    % bar shift -10pt here
    \\begin{axis}[bar shift=-10pt,hide axis]
    \\addplot coordinates {
"""
    for instance_name in instance_names
        figure_str *= "($(instance_name), $(Ltmcm4[instance_name]/Lmcmb[instance_name]))"
    end
    figure_str *= """};
    \\addplot coordinates {
"""
    for instance_name in instance_names
        figure_str *= "($(instance_name), $(Ltmcm2[instance_name]/Lmcmb[instance_name]))"
    end
    figure_str *= """};
    \\addplot coordinates {
"""
    for instance_name in instance_names
        figure_str *= "($(instance_name), $(Lmcmb[instance_name]/Lmcmb[instance_name]))"
    end
    figure_str *= """};
    \\end{axis}
"""

    # Delay
    figure_str *= """
    % zero bar shift here
    \\begin{axis}
    \\addplot coordinates {
"""
    for instance_name in instance_names
        figure_str *= "($(instance_name), $(Dtmcm4[instance_name]/Dmcmb[instance_name]))"
    end
    figure_str *= """};
    \\addplot coordinates {
"""
    for instance_name in instance_names
        figure_str *= "($(instance_name), $(Dtmcm2[instance_name]/Dmcmb[instance_name]))"
    end
    figure_str *= """};
    \\addplot coordinates {
"""
    for instance_name in instance_names
        figure_str *= "($(instance_name), $(Dmcmb[instance_name]/Dmcmb[instance_name]))"
    end
    figure_str *= """};
    %\\legend{\\strut \\TMCM\$_4\$, \\strut \\TMCM\$_2\$, \\strut \\MCMB}
    \\end{axis}
"""

    # Power
    figure_str *= """
    % and bar shift +10pt here
    \\begin{axis}[bar shift=10pt,hide axis]
    \\addplot coordinates {
"""
    for instance_name in instance_names
        figure_str *= "($(instance_name), $(Ptmcm4[instance_name]/Pmcmb[instance_name]))"
    end
    figure_str *= """};
    \\addplot coordinates {
"""
    for instance_name in instance_names
        figure_str *= "($(instance_name), $(Ptmcm2[instance_name]/Pmcmb[instance_name]))"
    end
    figure_str *= """};
    \\addplot coordinates {
"""
    for instance_name in instance_names
        figure_str *= "($(instance_name), $(Pmcmb[instance_name]/Pmcmb[instance_name]))"
    end
    figure_str *= """};
    \\end{axis}
"""

    figure_str *= """
\\end{tikzpicture}
\\caption{LUTS/Delay/Power ratio}\\label{fig:onebittruncerror}
\\end{figure}
"""

    open("$(@__DIR__)/tex/results_trunc.tex", "w") do writefile
        write(writefile, figure_str)
    end
    return nothing
end

function get_reduction(a::T, b::T) where T
    return (a-b)/a
end

function get_average_reduction(a::Dict{String, T}, b::Dict{String, T}; ifdifferent::Bool=false) where T
    all_reductions = Vector{Float64}()
    for current_key in keys(a)
        if haskey(b, current_key)
            if ifdifferent
                if a[current_key] != b[current_key]
                    push!(all_reductions, get_reduction(a[current_key], b[current_key]))
                end
            else
                push!(all_reductions, get_reduction(a[current_key], b[current_key]))
            end
        end
    end
    return round(mean(all_reductions)*10000)/100
end

function get_max_reduction(a::Dict{String, T}, b::Dict{String, T}; ifdifferent::Bool=false) where T
    all_reductions = Vector{Float64}()
    for current_key in keys(a)
        if haskey(b, current_key)
            if ifdifferent
                if a[current_key] != b[current_key]
                    push!(all_reductions, get_reduction(a[current_key], b[current_key]))
                end
            else
                push!(all_reductions, get_reduction(a[current_key], b[current_key]))
            end
        end
    end
    return round(maximum(all_reductions)*10000)/100
end

function get_min_reduction(a::Dict{String, T}, b::Dict{String, T}; ifdifferent::Bool=false) where T
    all_reductions = Vector{Float64}()
    for current_key in keys(a)
        if haskey(b, current_key)
            if ifdifferent
                if a[current_key] != b[current_key]
                    push!(all_reductions, get_reduction(a[current_key], b[current_key]))
                end
            else
                push!(all_reductions, get_reduction(a[current_key], b[current_key]))
            end
        end
    end
    return round(minimum(all_reductions)*10000)/100
end


function results_to_gain_command()
    NAmcma = Dict{String, Int}()
    NAmcmad = Dict{String, Int}()
    NAmcmb = Dict{String, Int}()
    NAtmcm = Dict{String, Int}()
    NAtmcm2 = Dict{String, Int}()
    NAtmcm4 = Dict{String, Int}()
    ADmcma = Dict{String, Int}()
    ADmcmad = Dict{String, Int}()
    ADmcmb = Dict{String, Int}()
    ADtmcm = Dict{String, Int}()
    ADtmcm2 = Dict{String, Int}()
    ADtmcm4 = Dict{String, Int}()
    Bmcma = Dict{String, Int}()
    Bmcmad = Dict{String, Int}()
    Bmcmb = Dict{String, Int}()
    Btmcm = Dict{String, Int}()
    Btmcm2 = Dict{String, Int}()
    Btmcm4 = Dict{String, Int}()
    Lmcma = Dict{String, Int}()
    Lmcmad = Dict{String, Int}()
    Lmcmb = Dict{String, Int}()
    Ltmcm = Dict{String, Int}()
    Ltmcm2 = Dict{String, Int}()
    Ltmcm4 = Dict{String, Int}()
    Dmcma = Dict{String, Float64}()
    Dmcmad = Dict{String, Float64}()
    Dmcmb = Dict{String, Float64}()
    Dtmcm = Dict{String, Float64}()
    Dtmcm2 = Dict{String, Float64}()
    Dtmcm4 = Dict{String, Float64}()
    Pmcma = Dict{String, Int}()
    Pmcmad = Dict{String, Int}()
    Pmcmb = Dict{String, Int}()
    Ptmcm = Dict{String, Int}()
    Ptmcm2 = Dict{String, Int}()
    Ptmcm4 = Dict{String, Int}()
    open("$(@__DIR__)/results_all.csv", "r") do readfile
        lines = readlines(readfile)
        for line in lines[2:end]
            # name	file_ag	method	min_ad	time	NA	ad	wl_in	onebit	epsilon_max	wl_out_full	wl_out	epsilon_frac	LUTs, Delay, Power
            data_str = split(line, ",")
            while length(data_str) < 16
                push!(data_str, "")
            end
            instance_name_init, _, method, min_ad_str, _, NA_str, ad_str, _, onebit_str, _, _, _, epsilon_frac_str, luts_str, delay_str, power_str = strip.(data_str)
            instance_name = replace(instance_name_init, "_" => "\\_")
            min_ad = parse(Bool, min_ad_str)
            epsilon_frac = parse(Int, split(epsilon_frac_str, "/")[2])
            if !isempty(onebit_str)
                if method == "mcm" && !min_ad
                    NAmcma[instance_name] = parse(Int, NA_str)
                    ADmcma[instance_name] = parse(Int, ad_str)
                    Bmcma[instance_name] = parse(Int, onebit_str)
                elseif method == "mcm" && min_ad
                    NAmcmad[instance_name] = parse(Int, NA_str)
                    ADmcmad[instance_name] = parse(Int, ad_str)
                    Bmcmad[instance_name] = parse(Int, onebit_str)
                elseif method == "mcmb"
                    NAmcmb[instance_name] = parse(Int, NA_str)
                    ADmcmb[instance_name] = parse(Int, ad_str)
                    Bmcmb[instance_name] = parse(Int, onebit_str)
                elseif method == "tmcm" && epsilon_frac == 1
                    NAtmcm[instance_name] = parse(Int, NA_str)
                    ADtmcm[instance_name] = parse(Int, ad_str)
                    Btmcm[instance_name] = parse(Int, onebit_str)
                elseif method == "tmcm" && epsilon_frac == 2
                    NAtmcm2[instance_name] = parse(Int, NA_str)
                    ADtmcm2[instance_name] = parse(Int, ad_str)
                    Btmcm2[instance_name] = parse(Int, onebit_str)
                elseif method == "tmcm" && epsilon_frac == 4
                    NAtmcm4[instance_name] = parse(Int, NA_str)
                    ADtmcm4[instance_name] = parse(Int, ad_str)
                    Btmcm4[instance_name] = parse(Int, onebit_str)
                end
            end
            if !isempty(luts_str)
                if method == "mcm" && !min_ad
                    Lmcma[instance_name] = parse(Int, luts_str)
                    Dmcma[instance_name] = parse(Float64, delay_str[1:(end-2)])
                    Pmcma[instance_name] = round(Int, 1000*parse(Float64, power_str))
                elseif method == "mcm" && min_ad
                    Lmcmad[instance_name] = parse(Int, luts_str)
                    Dmcmad[instance_name] = parse(Float64, delay_str[1:(end-2)])
                    Pmcmad[instance_name] = round(Int, 1000*parse(Float64, power_str))
                elseif method == "mcmb"
                    Lmcmb[instance_name] = parse(Int, luts_str)
                    Dmcmb[instance_name] = parse(Float64, delay_str[1:(end-2)])
                    Pmcmb[instance_name] = round(Int, 1000*parse(Float64, power_str))
                elseif method == "tmcm" && epsilon_frac == 1
                    Ltmcm[instance_name] = parse(Int, luts_str)
                    Dtmcm[instance_name] = parse(Float64, delay_str[1:(end-2)])
                    Ptmcm[instance_name] = round(Int, 1000*parse(Float64, power_str))
                elseif method == "tmcm" && epsilon_frac == 2
                    Ltmcm2[instance_name] = parse(Int, luts_str)
                    Dtmcm2[instance_name] = parse(Float64, delay_str[1:(end-2)])
                    Ptmcm2[instance_name] = round(Int, 1000*parse(Float64, power_str))
                elseif method == "tmcm" && epsilon_frac == 4
                    Ltmcm4[instance_name] = parse(Int, luts_str)
                    Dtmcm4[instance_name] = parse(Float64, delay_str[1:(end-2)])
                    Ptmcm4[instance_name] = round(Int, 1000*parse(Float64, power_str))
                end
            end
        end
    end

    gainLUTsOBAvsNA = get_average_reduction(Lmcmad, Lmcmb)
    gainOBAsOBAvsNA = get_average_reduction(Bmcmad, Bmcmb)
    gainLUTsThalfvsOBA = get_average_reduction(Bmcmb, Btmcm2)
    gainLUTsThalfvsNA = get_average_reduction(Bmcma, Btmcm2)
    gainOBAsTvsOBA = get_average_reduction(Bmcmb, Btmcm)
    percentdelayreduc = get_average_reduction(Dmcma, Dmcmad, ifdifferent=true)
    gainLUTsTvsOBA = get_average_reduction(Lmcmb, Ltmcm)
    gaindelayTvsOBA = get_average_reduction(Dmcmb, Dtmcm)
    gainpowerTvsOBA = get_average_reduction(Pmcmb, Ptmcm)
    gainOBAsThalfvsOBA = get_average_reduction(Bmcmb, Btmcm2)
    gainOBAsTquartervsOBA = get_average_reduction(Bmcmb, Btmcm4)
    nbinstanceADreduced = 0
    for current_key in keys(ADmcma)
        if haskey(ADmcmad, current_key)
            if ADmcmad[current_key] < ADmcma[current_key]
                nbinstanceADreduced += 1
            end
        end
    end

    figure_str = """
\\newcommand{\\gainLUTsOBAvsNA}{$gainLUTsOBAvsNA}
\\newcommand{\\gainOBAsOBAvsNA}{$gainOBAsOBAvsNA}
\\newcommand{\\gainOBAsTvsOBA}{$gainOBAsTvsOBA}
\\newcommand{\\percentdelayreduc}{$percentdelayreduc}
\\newcommand{\\gainLUTsTvsOBA}{$gainLUTsTvsOBA}
\\newcommand{\\gaindelayTvsOBA}{$gaindelayTvsOBA}
\\newcommand{\\gainpowerTvsOBA}{$gainpowerTvsOBA}
\\newcommand{\\gainOBAsThalfvsOBA}{$gainOBAsThalfvsOBA}
\\newcommand{\\gainOBAsTquartervsOBA}{$gainOBAsTquartervsOBA}
\\newcommand{\\nbinstanceADreduced}{$nbinstanceADreduced}
\\newcommand{\\gainLUTsThalfvsOBA}{$gainLUTsThalfvsOBA}
\\newcommand{\\gainLUTsThalfvsNA}{$gainLUTsThalfvsNA}
"""
    open("$(@__DIR__)/tex/results_gain.tex", "w") do writefile
        write(writefile, figure_str)
    end
    return nothing
end


function results_to_gain_plot()
    Lmcma = Dict{String, Int}()
    Lmcmad = Dict{String, Int}()
    Lmcmb = Dict{String, Int}()
    Ltmcm = Dict{String, Int}()
    Dmcma = Dict{String, Float64}()
    Dmcmad = Dict{String, Float64}()
    Dmcmb = Dict{String, Float64}()
    Dtmcm = Dict{String, Float64}()
    Pmcma = Dict{String, Int}()
    Pmcmad = Dict{String, Int}()
    Pmcmb = Dict{String, Int}()
    Ptmcm = Dict{String, Int}()
    instance_names = Vector{String}()
    open("$(@__DIR__)/results_all.csv", "r") do readfile
        lines = readlines(readfile)
        for line in lines[2:end]
            # name	file_ag	method	min_ad	time	NA	ad	wl_in	onebit	epsilon_max	wl_out_full	wl_out	epsilon_frac	LUTs, Delay, Power
            data_str = split(line, ",")
            while length(data_str) < 16
                push!(data_str, "")
            end
            instance_name_init, _, method, min_ad_str, _, _, _, _, _, _, _, _, epsilon_frac_str, luts_str, delay_str, power_str = strip.(data_str)
            instance_name_init = instance_name_init[1]*(occursin("PASS", instance_name_init) ? "P" : ".")*instance_name_init[findfirst("_", instance_name_init)[1]:end]
            #instance_name = replace(instance_name_init, "_" => "\$_{")*"}\$"
            instance_name = replace(instance_name_init, "_" => "")
            push!(instance_names, instance_name)
            min_ad = parse(Bool, min_ad_str)
            epsilon_frac = parse(Int, split(epsilon_frac_str, "/")[2])
            if !isempty(luts_str)
                if method == "mcm" && !min_ad
                    Lmcma[instance_name] = parse(Int, luts_str)
                    Dmcma[instance_name] = parse(Float64, delay_str[1:(end-2)])
                    Pmcma[instance_name] = round(Int, 1000*parse(Float64, power_str))
                elseif method == "mcm" && min_ad
                    Lmcmad[instance_name] = parse(Int, luts_str)
                    Dmcmad[instance_name] = parse(Float64, delay_str[1:(end-2)])
                    Pmcmad[instance_name] = round(Int, 1000*parse(Float64, power_str))
                elseif method == "mcmb"
                    Lmcmb[instance_name] = parse(Int, luts_str)
                    Dmcmb[instance_name] = parse(Float64, delay_str[1:(end-2)])
                    Pmcmb[instance_name] = round(Int, 1000*parse(Float64, power_str))
                elseif method == "tmcm" && epsilon_frac == 1
                    Ltmcm[instance_name] = parse(Int, luts_str)
                    Dtmcm[instance_name] = parse(Float64, delay_str[1:(end-2)])
                    Ptmcm[instance_name] = round(Int, 1000*parse(Float64, power_str))
                end
            end
        end
    end
    unique!(instance_names)
    instance_name_to_delete = falses(length(instance_names))
    for i in 1:length(instance_names)
        instance_name = instance_names[i]
        if !(haskey(Lmcma, instance_name)) || !(haskey(Lmcmad, instance_name)) || !(haskey(Lmcmb, instance_name)) || !(haskey(Ltmcm, instance_name))
            instance_name_to_delete[i] = true
        end
    end
    deleteat!(instance_names, instance_name_to_delete)

    figure_str = """
\\begin{figure*}
\\centering
\\begin{tikzpicture}
    \\begin{axis}[
            ybar,
            ytick pos=left,
            xtick pos=bottom,
            %bar width=0.12,
            legend style={at={(0.5,-0.25)}, anchor=north, legend columns=2},
            every axis legend/.code={\\let\\addlegendentry\\relax},
            %ymin=0,
            width=19cm,
            height=5cm,
            ylabel={\\#LUTs},
            symbolic x coords={$(join(instance_names, ","))},
            xtick=data,
            point meta=explicit symbolic
        ]
"""
    figure_str *= """
        \\addplot[legend entry=\\MCMad reduction compared to \\MCMA, mcmad, fill=mcmadfill] coordinates {
"""
    for instance_name in instance_names
        figure_str *= "($instance_name, $(round(get_reduction(Lmcma[instance_name], Lmcmad[instance_name])*10000)/100))"
    end
    figure_str *= """
        };
"""
    figure_str *= """
        \\addplot[legend entry=\\MCMB reduction compared to \\MCMad, mcmb, fill=mcmbfill] coordinates {
"""
    for instance_name in instance_names
        figure_str *= "($instance_name, $(round(get_reduction(Lmcmad[instance_name], Lmcmb[instance_name])*10000)/100))"
    end
    figure_str *= """
        };
"""
    figure_str *= """
        \\addplot[legend entry=\\TMCM reduction compared to \\MCMB, tmcm, fill=tmcmfill] coordinates {
"""
    for instance_name in instance_names
        figure_str *= "($instance_name, $(round(get_reduction(Lmcmb[instance_name], Ltmcm[instance_name])*10000)/100))"
    end
    figure_str *= """
        };
"""
    figure_str *= """
        \\addplot[legend entry=\\TMCM reduction compared to \\MCMad, tmcm, fill=tmcmfill] coordinates {
"""
    for instance_name in instance_names
        figure_str *= "($instance_name, $(round(get_reduction(Lmcmad[instance_name], Ltmcm[instance_name])*10000)/100))"
    end
    figure_str *= """
        };
"""

    figure_str *= """
    \\end{axis}
\\end{tikzpicture}
"""

    figure_str *= """
\\begin{tikzpicture}
    \\begin{axis}[
            ybar,
            ytick pos=left,
            xtick pos=bottom,
            %bar width=0.12,
            legend style={at={(0.5,-0.25)}, anchor=north, legend columns=2},
            every axis legend/.code={\\let\\addlegendentry\\relax},
            %ymin=0,
            width=19cm,
            height=5cm,
            ylabel={Delay},
            symbolic x coords={$(join(instance_names, ","))},
            xtick=data,
            point meta=explicit symbolic
        ]
"""
    figure_str *= """
        \\addplot[legend entry=\\MCMad reduction compared to \\MCMA, mcmad, fill=mcmadfill] coordinates {
"""
    for instance_name in instance_names
        figure_str *= "($instance_name, $(round(get_reduction(Dmcma[instance_name], Dmcmad[instance_name])*10000)/100))"
    end
    figure_str *= """
        };
"""
    figure_str *= """
        \\addplot[legend entry=\\MCMB reduction compared to \\MCMad, mcmb, fill=mcmbfill] coordinates {
"""
    for instance_name in instance_names
        figure_str *= "($instance_name, $(round(get_reduction(Dmcmad[instance_name], Dmcmb[instance_name])*10000)/100))"
    end
    figure_str *= """
        };
"""
    figure_str *= """
        \\addplot[legend entry=\\TMCM reduction compared to \\MCMB, tmcm, fill=tmcmfill] coordinates {
"""
    for instance_name in instance_names
        figure_str *= "($instance_name, $(round(get_reduction(Dmcmb[instance_name], Dtmcm[instance_name])*10000)/100))"
    end
    figure_str *= """
        };
"""
    figure_str *= """
        \\addplot[legend entry=\\TMCM reduction compared to \\MCMad, tmcm, fill=tmcmfill] coordinates {
"""
    for instance_name in instance_names
        figure_str *= "($instance_name, $(round(get_reduction(Dmcmad[instance_name], Dtmcm[instance_name])*10000)/100))"
    end
    figure_str *= """
        };
"""
    figure_str *= """
    \\end{axis}
\\end{tikzpicture}
"""

    figure_str *= """
    \\begin{tikzpicture}
    \\begin{axis}[
            ybar,
            ytick pos=left,
            xtick pos=bottom,
            %bar width=0.12,
            legend style={at={(0.5,-0.25)}, anchor=north, legend columns=2},
            %ymin=0,
            width=19cm,
            height=5cm,
            ylabel={Power},
            symbolic x coords={$(join(instance_names, ","))},
            xtick=data,
            point meta=explicit symbolic
        ]
"""
    figure_str *= """
        \\addplot[legend entry=\\MCMad reduction compared to \\MCMA, mcmad, fill=mcmadfill] coordinates {
"""
    for instance_name in instance_names
        figure_str *= "($instance_name, $(round(get_reduction(Pmcma[instance_name], Pmcmad[instance_name])*10000)/100))"
    end
    figure_str *= """
        };
"""
    figure_str *= """
        \\addplot[legend entry=\\MCMB reduction compared to \\MCMad, mcmb, fill=mcmbfill] coordinates {
"""
    for instance_name in instance_names
        figure_str *= "($instance_name, $(round(get_reduction(Pmcmad[instance_name], Pmcmb[instance_name])*10000)/100))"
    end
    figure_str *= """
        };
"""
    figure_str *= """
        \\addplot[legend entry=\\TMCM reduction compared to \\MCMB, tmcm, fill=tmcmfill] coordinates {
"""
    for instance_name in instance_names
        figure_str *= "($instance_name, $(round(get_reduction(Pmcmb[instance_name], Ptmcm[instance_name])*10000)/100))"
    end
    figure_str *= """
        };
"""
    figure_str *= """
        \\addplot[legend entry=\\TMCM reduction compared to \\MCMad, tmcm, fill=tmcmfill] coordinates {
"""
    for instance_name in instance_names
        figure_str *= "($instance_name, $(round(get_reduction(Pmcmad[instance_name], Ptmcm[instance_name])*10000)/100))"
    end
    figure_str *= """
        };
"""

    figure_str *= """
    \\end{axis}
\\end{tikzpicture}
\\caption{}
\\end{figure*}
"""

    open("$(@__DIR__)/tex/results_gainbarplot.tex", "w") do writefile
        write(writefile, figure_str)
    end
    return nothing
end



function results_to_gain_plot_average()
    Lmcma = Dict{String, Int}()
    Lmcmad = Dict{String, Int}()
    Lmcmb = Dict{String, Int}()
    Ltmcm = Dict{String, Int}()
    Dmcma = Dict{String, Float64}()
    Dmcmad = Dict{String, Float64}()
    Dmcmb = Dict{String, Float64}()
    Dtmcm = Dict{String, Float64}()
    Pmcma = Dict{String, Int}()
    Pmcmad = Dict{String, Int}()
    Pmcmb = Dict{String, Int}()
    Ptmcm = Dict{String, Int}()
    open("$(@__DIR__)/results_all.csv", "r") do readfile
        lines = readlines(readfile)
        for line in lines[2:end]
            # name	file_ag	method	min_ad	time	NA	ad	wl_in	onebit	epsilon_max	wl_out_full	wl_out	epsilon_frac	LUTs, Delay, Power
            data_str = split(line, ",")
            while length(data_str) < 16
                push!(data_str, "")
            end
            instance_name_init, _, method, min_ad_str, _, _, _, _, _, _, _, _, epsilon_frac_str, luts_str, delay_str, power_str = strip.(data_str)
            instance_name = replace(instance_name_init, "_" => "\\_")
            min_ad = parse(Bool, min_ad_str)
            epsilon_frac = parse(Int, split(epsilon_frac_str, "/")[2])
            if !isempty(luts_str)
                if method == "mcm" && !min_ad
                    Lmcma[instance_name] = parse(Int, luts_str)
                    Dmcma[instance_name] = parse(Float64, delay_str[1:(end-2)])
                    Pmcma[instance_name] = round(Int, 1000*parse(Float64, power_str))
                elseif method == "mcm" && min_ad
                    Lmcmad[instance_name] = parse(Int, luts_str)
                    Dmcmad[instance_name] = parse(Float64, delay_str[1:(end-2)])
                    Pmcmad[instance_name] = round(Int, 1000*parse(Float64, power_str))
                elseif method == "mcmb"
                    Lmcmb[instance_name] = parse(Int, luts_str)
                    Dmcmb[instance_name] = parse(Float64, delay_str[1:(end-2)])
                    Pmcmb[instance_name] = round(Int, 1000*parse(Float64, power_str))
                elseif method == "tmcm" && epsilon_frac == 2
                    Ltmcm[instance_name] = parse(Int, luts_str)
                    Dtmcm[instance_name] = parse(Float64, delay_str[1:(end-2)])
                    Ptmcm[instance_name] = round(Int, 1000*parse(Float64, power_str))
                end
            end
        end
    end

    max_reduction_percent = 60

    figure_str = """
\\def\\varheight{5cm}
\\def\\varshift{12pt}
\\def\\varenlarge{30pt}
\\begin{figure}
\\small
\\centering
\\begin{tikzpicture}
"""
    #
    figure_str *= """
    \\begin{axis}[
            %ybar,
            ybar stacked,
            bar shift=0pt,
            %hide axis,
            ytick pos=left,
            xtick pos=bottom,
            %bar width=0.12,
            legend style={at={(0.5,-0.25)}, /tikz/every even column/.append style={column sep=-2mm}, anchor=north, legend columns=2},
            %every axis legend/.code={\\let\\addlegendentry\\relax},
            enlarge x limits={abs=\\varenlarge},
            ymin=-10,
        	ymax=$(max_reduction_percent+5),
            ytick={0,20,...,$(max_reduction_percent)},
            ymajorgrids=true,
        	width=0.9\\linewidth,
            height=\\varheight,
            ylabel={Reduction, \\%},
            symbolic x coords={\\#LUTs, Delay, Power},
            xtick=data,
            point meta=explicit symbolic
        ]
"""
    figure_str *= """
        \\addlegendimage{mcmad, fill=mcmadfill}
        \\addlegendentry{}
        \\addlegendimage{mcmadmax, fill=mcmadfillmax}
        \\addlegendentry{\\MCMad average/max reduction compared to \\MCMA}
"""
    figure_str *= """
        \\addplot[legend entry=\\phantom{.}, mcmb, fill=mcmbfill] coordinates {
"""
    figure_str *= "(\\#LUTs, $(get_average_reduction(Lmcma, Lmcmb)))"
    figure_str *= "(Delay, $(get_average_reduction(Dmcma, Dmcmb)))"
    figure_str *= "(Power, $(get_average_reduction(Pmcma, Pmcmb)))\n"
    figure_str *= """
        };
"""
    figure_str *= """
        \\addplot[legend entry=\\MCMB average/max reduction compared to \\MCMA, mcmbmax, fill=mcmbfillmax] coordinates {
"""
    figure_str *= "(\\#LUTs, $(get_max_reduction(Lmcma, Lmcmb)-get_average_reduction(Lmcma, Lmcmb)))"
    figure_str *= "(Delay, $(get_max_reduction(Dmcma, Dmcmb)-get_average_reduction(Dmcma, Dmcmb)))"
    figure_str *= "(Power, $(get_max_reduction(Pmcma, Pmcmb)-get_average_reduction(Pmcma, Pmcmb)))\n"
    figure_str *= """
        };
"""
    figure_str *= """
        \\addlegendimage{tmcm, fill=tmcmfill}
        \\addlegendentry{}
        \\addlegendimage{tmcmmax, fill=tmcmfillmax}
        \\addlegendentry{\\TMCM average/max reduction compared to \\MCMA}
"""
    figure_str *= """
    \\end{axis}
"""
    #
    figure_str *= """
    \\begin{axis}[
            %ybar,
            ybar stacked,
            bar shift=-\\varshift-2.5pt,
            hide axis,
            ytick pos=left,
            xtick pos=bottom,
            %bar width=0.12,
            legend style={at={(0.5,-0.25)}, anchor=north, legend columns=1},
            every axis legend/.code={\\let\\addlegendentry\\relax},
            enlarge x limits={abs=\\varenlarge},
            ymin=-10,
            ymax=$(max_reduction_percent+5),
            width=0.9\\linewidth,
            height=\\varheight,
            ylabel={Reduction, \\%},
            symbolic x coords={\\#LUTs, Delay, Power},
            xtick=data,
            point meta=explicit symbolic
        ]
"""
    figure_str *= """
        \\addplot[legend entry=\\MCMad average reduction compared to \\MCMA, mcmad, fill=mcmadfill] coordinates {
"""
    figure_str *= "(\\#LUTs, $(get_average_reduction(Lmcma, Lmcmad)))"
    figure_str *= "(Delay, $(get_average_reduction(Dmcma, Dmcmad)))"
    figure_str *= "(Power, $(get_average_reduction(Pmcma, Pmcmad)))\n"
    figure_str *= """
        };
"""
    figure_str *= """
        \\addplot[legend entry=\\MCMad max reduction compared to \\MCMA, mcmadmax, fill=mcmadfillmax] coordinates {
"""
    figure_str *= "(\\#LUTs, $(get_max_reduction(Lmcma, Lmcmad)-get_average_reduction(Lmcma, Lmcmad)))"
    figure_str *= "(Delay, $(get_max_reduction(Dmcma, Dmcmad)-get_average_reduction(Dmcma, Dmcmad)))"
    figure_str *= "(Power, $(get_max_reduction(Pmcma, Pmcmad)-get_average_reduction(Pmcma, Pmcmad)))\n"
    figure_str *= """
        };
"""
    figure_str *= """
    \\end{axis}
"""
    #
    figure_str *= """
    \\begin{axis}[
            %ybar,
            ybar stacked,
            bar shift=\\varshift,
            hide axis,
            ytick pos=left,
            xtick pos=bottom,
            %bar width=0.12,
            legend style={at={(0.5,-0.25)}, anchor=north, legend columns=1},
            every axis legend/.code={\\let\\addlegendentry\\relax},
            enlarge x limits={abs=\\varenlarge},
            ymin=-10,
            ymax=$(max_reduction_percent+5),
        	width=0.9\\linewidth,
            height=\\varheight,
            ylabel={Reduction, \\%},
            symbolic x coords={\\#LUTs, Delay, Power},
            xtick=data,
            point meta=explicit symbolic
        ]
"""
    figure_str *= """
        \\addplot[legend entry=\\TMCM average reduction compared to \\MCMA, tmcm, fill=tmcmfill] coordinates {
"""
    figure_str *= "(\\#LUTs, $(get_average_reduction(Lmcma, Ltmcm)))"
    figure_str *= "(Delay, $(get_average_reduction(Dmcma, Dtmcm)))"
    figure_str *= "(Power, $(get_average_reduction(Pmcma, Ptmcm)))\n"
    figure_str *= """
        };
"""
    figure_str *= """
        \\addplot[legend entry=\\TMCM max reduction compared to \\MCMA, tmcmmax, fill=tmcmfillmax] coordinates {
"""
    figure_str *= "(\\#LUTs, $(get_max_reduction(Lmcma, Ltmcm)-get_average_reduction(Lmcma, Ltmcm)))"
    figure_str *= "(Delay, $(get_max_reduction(Dmcma, Dtmcm)-get_average_reduction(Dmcma, Dtmcm)))"
    figure_str *= "(Power, $(get_max_reduction(Pmcma, Ptmcm)-get_average_reduction(Pmcma, Ptmcm)))\n"
    figure_str *= """
        };
"""
    figure_str *= """
    \\end{axis}
"""

#     figure_str *= """
#         \\addplot[legend entry=\\TMCM reduction compared to \\MCMad, tmcm, fill=tmcmfill] coordinates {
# """
#     figure_str *= "(\\#LUTs, $(get_average_reduction(Lmcmad, Ltmcm)))"
#     figure_str *= "(Delay, $(get_average_reduction(Dmcmad, Dtmcm)))"
#     figure_str *= "(Power, $(get_average_reduction(Pmcmad, Ptmcm)))"
#     figure_str *= """
#         };
# """

    figure_str *= """
\\end{tikzpicture}
\\caption{}\\label{fig:averageandmaxgain}
% Min reduction
% AD/Adders
% \\#LUTs, $(get_min_reduction(Lmcma, Lmcmad))
% Delay, $(get_min_reduction(Dmcma, Dmcmad))
% Power, $(get_min_reduction(Pmcma, Pmcmad))
% Bits/AD
% \\#LUTs, $(get_min_reduction(Lmcmad, Lmcmb))
% Delay, $(get_min_reduction(Dmcmad, Dmcmb))
% Power, $(get_min_reduction(Pmcmad, Pmcmb))
% Truncation/Bits
% \\#LUTs, $(get_min_reduction(Lmcmb, Ltmcm))
% Delay, $(get_min_reduction(Dmcmb, Dtmcm))
% Power, $(get_min_reduction(Pmcmb, Ptmcm))
\\end{figure}
"""

    open("$(@__DIR__)/tex/results_gainaveragebarplot.tex", "w") do writefile
        write(writefile, figure_str)
    end
    return nothing
end



function read_results()
    results_to_table()
    results_to_correlation()
    results_to_ad()
    results_to_bars()
    results_to_gain_command()
    results_to_gain_plot_average()
    results_to_gain_plot()
    return nothing
end
