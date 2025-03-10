# jMCM
Tool to generate and solve MILP models used to obtain minimal cost adder graphs for Multiple Constant Multiplication (MCM) problems.

Require AdderGraphs v0.1.0:

## Features

- **Adder Depth Constraints**: Constraint on the maximal adder depth.
- **Pipeline Support**: Option to enable pipelining in the adder graph implementation.
- **Minimize the Number of Adders**: Minimize the adder count, solving an MCM-Adders problem.
- **Minimize the Number of One-Bit Adders**: Minimize the one-bit adder count, solving an MCM-Bits problem.
- **Internal Truncations**: Possibility of internal adder truncations given an output error bound.
- **Minimize Adder Depth**: Minimize the adder depth as a secondary objective.

## Prerequisites

Before running `jMCM.jl`, ensure that the following Julia packages are installed:

- `JuMP`: A modeling language for mathematical optimization.
- `Gurobi`, `CPLEX`, `SCIP`, etc.: An MILP optimization solver. Ensure that the solver is installed and properly licensed.
- `AdderGraphs`: A package for working with adder graphs.

You can install these packages using Julia's package manager:

```julia
using Pkg
Pkg.add("JuMP")
#Pkg.add("Gurobi")
#Pkg.add("CPLEX")
Pkg.add("SCIP")
Pkg.add(url="git@github.com:remi-garcia/addergraphs.git")
```

## Usage

To run the script, use the Julia command line interface and provide the necessary arguments:

```bash
julia jMCM.jl [target_constants] [options]
```

### Arguments

- `target_constants`: A space-separated list of integers representing the constants to be implemented using adder graphs.

### Options

- `timelimit=<float>`: Set a time limit (in seconds) for the solver.
- `wIn=<int>` (optional): Specify the input word size, for MCM-Bits.
- `wOut=<int>` (optional): Specify the output word size, to include internal truncations.
- `pipeline=<bool>` (optional): Enable (`true`) or disable (`false`) pipelining to solve the PMCM problem. Default: `false`.
- `verbose=<bool>` (optional): Enable (`true`) or disable (`false`) verbose output. Default: `false`.
- `min_ad=<bool>` (optional): Enable (`true`) or disable (`false`) minimization of adder depth. Default: `false`.
- `nb_adders_start=<int>` (optional): Set the initial number of adders.
- `use_rpag=<bool>` (optional): Enable (`true`) or disable (`false`) the use of RPAG for the warm start solution. Default: `false`.
- `use_mcm=<bool>` (optional): Enable (`true`) or disable (`false`) a warm start by solving the vanilla MCM-Adders problem. Default: `false`.
- `ws_timelimit=<float>` (optional): Set a time limit for the MCM warm start optimization.
- `threads=<int>` (optional): Specify the number of threads to use for the solver.
- `file_ag=<string>` (optional): Specify the output file name for the adder graph.

### Example

```bash
julia jMCM.jl 5 11 19 timelimit=60.0 pipeline=false verbose=true
```

This command optimizes the implementation of constants 5, 11, and 19 with a time limit of 60 seconds, pipelining disabled, and verbose output.

This script generates the `addergraph.txt` file which contains the adder graph representation.
