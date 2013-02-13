#!/bin/bash
set -e
#set -x

if [ -n "$1" ]; then
    pretend=echo
else
    pretend=
fi

export USERNAME=ytaraday
PROJECTS="cinder glance horizon keystone nova quantum swift"
CLIENT_PROJECTS="cinder glance keystone nova quantum swift"
for prj in $CLIENT_PROJECTS; do
    PROJECTS="$PROJECTS python-${prj}client"
done
BLANK=70e09e6cf5c0b4792811d6dbf97872d145b4c4d8

for prj in $PROJECTS; do
    case $prj in
        python-* )
            branch=master;;
        * )
            branch=stable/folsom;;
    esac
    git remote add gerrit-mirantis ssh://$USERNAME@gerrit.mirantis.com:29418/openstack/$prj.git
    git fetch -q gerrit-mirantis openstack-ci/fuel/folsom
    git tag t1 FETCH_HEAD
    git remote add github git://github.com/openstack/$prj.git
    git fetch -q --tags github $branch
    tag_base=$(git describe FETCH_HEAD)
    tag_base=${tag_base%%-*}
    [ -n "$pretend" ] && echo -n "$prj "
    $pretend git push gerrit-mirantis refs/tags/t1:refs/tags/openstack-ci/fuel/$tag_base/2.0
    rm .git/refs/tags/*
    git remote rm gerrit-mirantis
    git remote rm github
done
