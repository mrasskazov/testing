#!/bin/bash -x

cd
git clone git@bitbucket.org:osci-jenkins/testing.git -b node_prepare
./testing/node_prepare/run-job.sh
