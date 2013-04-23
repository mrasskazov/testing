#!/bin/bash -ex
. subr

export USERNAME=ytaraday
PROJECTS=" oslo.config "
add_client_projects
TARGET_VERSION=grizzly
FUEL_VERSION=2.1
init_repo

for prj in $PROJECTS; do
    add_mirantis_remote
    cleanup_tags
    git fetch -q --tags mirantis-$prj
    git fetch -q mirantis-$prj master
    tag_base=$(git describe --tags FETCH_HEAD)
    tag_base=${tag_base%%-*}
    git push mirantis-$prj $tag_base^0:refs/heads/openstack-ci/$TARGET_VERSION
    git push mirantis-$prj $tag_base^0:refs/tags/openstack-ci/$tag_base
    git push mirantis-$prj $tag_base^0:refs/tags/openstack-ci/fuel/$tag_base/$FUEL_VERSION
    cleanup_all
done
