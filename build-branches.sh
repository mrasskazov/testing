#!/bin/bash -ex
. subr

export USERNAME=ytaraday
add_nonclient_projects but tempest
BLANK=2451ea06740f17b46e0811f209e7abf88261d97b
TARGET_VERSION=grizzly

for prj in $PROJECTS; do
    add_mirantis_remote
    git checkout $BLANK
    set_gitreview "openstack-ci/build/$TARGET_VERSION"
    git add .gitreview
    git commit --amend -m 'Initial commit.'
    echo git push -f mirantis-$prj HEAD:refs/heads/openstack-ci/build/$TARGET_VERSION
    cleanup_all
done
