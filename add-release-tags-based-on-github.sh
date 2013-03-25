#!/bin/bash
set -e
quiet=-q
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
    git remote add mirantis-$prj ssh://$USERNAME@gerrit.mirantis.com:29418/openstack/$prj.git
    git fetch $quiet mirantis-$prj openstack-ci/folsom
    git tag t1 FETCH_HEAD
    git fetch $quiet --tags mirantis-$prj openstack-ci/fuel/folsom
    git tag t2 FETCH_HEAD
    git remote add github-$prj git://github.com/openstack/$prj.git
    git fetch $quiet --tags github-$prj $branch
    $pretend git push mirantis-$prj $(for t in $(git tag -l | grep openstack-ci); do echo :$t; done)
    tag_base=$(git describe --tags t1~)
    tag_base=${tag_base%%-*}
    [ -n "$pretend" ] && echo -n "$prj "
    $pretend git push mirantis-$prj refs/tags/t1:refs/tags/openstack-ci/$tag_base refs/tags/t2:refs/tags/openstack-ci/fuel/$tag_base/2.0
    rm -r .git/refs/tags/*
    git remote rm mirantis-$prj
    git remote rm github-$prj
done
