#!/bin/bash
set -e
set -x

export USERNAME=ytaraday
PROJECTS="cinder glance keystone nova quantum swift"
BLANK=70e09e6cf5c0b4792811d6dbf97872d145b4c4d8

for sprj in $PROJECTS; do
    prj=python-${sprj}client
    git fetch git://github.com/openstack/$prj master
    git checkout FETCH_HEAD
    cat > .gitreview <<END
[gerrit]
host=gerrit.mirantis.com
project=openstack/$prj.git
defaultremote=gerrit-mirantis
defaultbranch=openstack-ci/folsom
END
    git add .gitreview
    git commit -m 'Set .gitreview to Mirantis Gerrit'
    git review -s
    git push gerrit-mirantis HEAD:refs/heads/openstack-ci/folsom
    git checkout $BLANK
    cat > .gitreview <<END
[gerrit]
host=gerrit.mirantis.com
project=openstack/$prj.git
defaultremote=gerrit-mirantis
defaultbranch=openstack-ci/build/folsom
END
    git add .gitreview
    git commit -m 'Add .gitrevire pointing to Miranis Gerrit'
    git push gerrit-mirantis HEAD:refs/heads/openstack-ci/build/folsom
    git remote rm gerrit-mirantis
done
