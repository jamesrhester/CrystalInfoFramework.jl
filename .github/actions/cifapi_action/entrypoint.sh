#!/bin/bash -l

# get latest cifapi

git clone https://github.com/COMCIFS/cif_api cif_api
pushd cif_api
./configure
make install

