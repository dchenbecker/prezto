#!/bin/zsh
# Load functions
for file in $(dirname $0)/src/{map,each,filter,fold,foldright,loop-magic,docs}.zsh
do
  . $file
done
