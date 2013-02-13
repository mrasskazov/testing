#!/bin/bash
set -e
set -x

export USERNAME=ytaraday
PROJECTS="cinder glance horizon keystone nova quantum swift tempest"
CLIENT_PROJECTS="cinder glance keystone nova quantum swift"
for prj in $CLIENT_PROJECTS; do
    PROJECTS="$PROJECTS python-${prj}client"
done
BLANK=70e09e6cf5c0b4792811d6dbf97872d145b4c4d8

for prj in $PROJECTS; do
    git remote add gerrit-mirantis ssh://$USERNAME@gerrit.mirantis.com:29418/openstack/$prj.git
    git fetch gerrit-mirantis openstack-ci/folsom
    git checkout FETCH_HEAD
    cat > .gitreview <<END
[gerrit]
host=gerrit.mirantis.com
project=openstack/$prj.git
defaultremote=gerrit-mirantis
defaultbranch=openstack-ci/fuel/folsom
END
    git add .gitreview
    git commit -m 'Set .gitreview to Mirantis Gerrit'
    #git commit --amend
    git push gerrit-mirantis HEAD:refs/heads/openstack-ci/fuel/folsom
    git push gerrit-mirantis HEAD:refs/heads/openstack-ci/folsom
    git remote rm gerrit-mirantis
done
