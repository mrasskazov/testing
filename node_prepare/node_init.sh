#!/bin/bash -x

cd
git clone https://github.com/mrasskazov/testing.git -b fuel/stable/havana
pushd testing
    ./node_prepare/node_init.py
popd
./testing/node_prepare/run-job.sh
