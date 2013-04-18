#!/bin/bash -e
. subr

export USERNAME=ytaraday
add_client_projects

for prj in $PROJECTS; do
    add_mirantis_remote
    cleanup_tags
    git fetch mirantis-$prj openstack-ci/build/folsom
    git checkout FETCH_HEAD
    set_gitreview openstack-ci/build/grizzly
    git commit -m 'Switch .gitreview to grizzly branch' .gitreview
    set -x
    git push mirantis-$prj HEAD:refs/heads/openstack-ci/build/grizzly
    set +x
    cleanup_all
done
