#!/bin/bash

# Unpack binaries. For long-term portability, it's best to
# avoid TACC modules

module purge
module load TACC

tar -xzf bin.tgz
export PATH=$HOME/bin:$PATH:./bin

databaseFasta=$1

NAME="${databaseFasta}.zip"

bwa index -6 ${databaseFasta}
FILES=$(ls "${databaseFasta}".*)
zip -1 ${NAME} ${FILES} ${databaseFasta} && rm -rf ${FILES} $databaseFasta
