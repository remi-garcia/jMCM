#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
# for i in {21,22,32,33,34,47,56,57,58,76,77}
for i in {1..86}
do
    julia $SCRIPT_DIR/benchmarks.jl $i $@
# >> $SCRIPT_DIR/fullrun.txt
done
