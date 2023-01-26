#!/bin/bash

# project_dir=$(pwd)
# source_dir=$project_dir/sources
# obj_dir=$project_dir/obj

# runtime_dir=$project_dir/.

# sources=(./main.d)

# compiler_args=


# mkdir -p obj
# mkdir -p bin
# mkdir -p bin/debug
# mkdir -p bin/release

# for i in ${!sources[*]}
# do
#   sources[i]="\"$source_dir/${sources[i]}\""
# done

ldc2 -g -od=./obj -of=./main main.d lexer.d parser.d compiler.d