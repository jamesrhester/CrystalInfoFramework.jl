#!/bin/bash -l

# get latest cifapi

git clone https://github.com/COMCIFS/cif_api cif_api
pushd cif_api
./configure --without-docs --prefix=$GITHUB_WORKSPACE
make install

# latest icu libraries
cp -n `find /usr/lib -name libicuio.so*` $GITHUB_WORKSPACE/lib
cp -n `find /usr/lib -name libicui18n.so*` $GITHUB_WORKSPACE/lib
cp -n `find /usr/lib -name libicuuc.so*` $GITHUB_WORKSPACE/lib
cp -n `find /usr/lib -name libicudata.so*` $GITHUB_WORKSPACE/lib
