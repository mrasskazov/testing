#!/bin/bash -e
. subr

export USERNAME=ytaraday
add_nonclient_projects but tempest
TARGET_VERSION=grizzly

for prj in $PROJECTS; do
    add_mirantis_remote
    add_github_remote
    branches=$(git ls-remote --heads github-$prj)
    for option in stable/$TARGET_VERSION milestone-proposed master; do
        case $branches in
            *refs/heads/$option* ) source_branch=$option; break;;
        esac
    done
    cleanup_tags
    git fetch -q --tags github-$prj
    git fetch -q github-$prj $source_branch
    tag_base=$(git describe --tags FETCH_HEAD)
    tag_base=${tag_base%%-*}
    git tag t1 FETCH_HEAD
    set -x
    git push mirantis-$prj FETCH_HEAD:refs/heads/openstack-ci/$TARGET_VERSION
    git push mirantis-$prj refs/tags/t1:refs/tags/openstack-ci/$tag_base/0.1
    set +x
    cleanup_all
done
