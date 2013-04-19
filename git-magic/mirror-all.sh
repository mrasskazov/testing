#!/bin/bash -ex

. subr
: ${USERNAME:=openstack-mirrorer-jenkins}
add_all_projects
init_repo

for prj in $PROJECTS; do
    add_github_remote
    add_mirantis_remote
    git fetch mirantis-$prj --no-tags
    git fetch github-$prj
    to_push=
    for branch in $(find "$GIT_DIR/refs/remotes/github-$prj" -type f); do
        local_ref=${branch##$GIT_DIR/}
        remote_ref=refs/heads/${local_ref##refs/remotes/github-$prj/}
        to_push="$to_push $local_ref:$remote_ref"
    done
    git push --force mirantis-$prj --tags $to_push
    cleanup_all
done
