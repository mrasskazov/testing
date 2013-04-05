#!/bin/bash -e
. subr

export USERNAME=ytaraday
add_client_projects
TARGET_VERSION=grizzly

for prj in $PROJECTS; do
    add_mirantis_remote
    add_github_remote
    cleanup_tags
    git fetch -q --tags github-$prj
    git fetch -q github-$prj master
    tag_base=$(git describe --tags FETCH_HEAD)
    tag_base=${tag_base%%-*}
    set -x
    git push mirantis-$prj $tag_base^0:refs/heads/openstack-ci/$TARGET_VERSION
    git push mirantis-$prj $tag_base^0:refs/tags/openstack-ci/$tag_base
    git push mirantis-$prj $tag_base^0:refs/tags/openstack-ci/fuel/$tag_base/2.1
    set +x
    cleanup_all
done
