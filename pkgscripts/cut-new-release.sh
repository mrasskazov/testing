#!/bin/bash
# Cut new release
# Usage: cut-new-release.sh branch [release]

# Determines next release # for your tag if release not specified and increments by one
# Needs to be run from inside one of our component git trees
# Release format: fuel/2012.2.3/2.0.8
# python client libs will skip 2012.2.3 and reuse their branch version

components="cinder glance horizon keystone swift nova python-cinderclient python-glanceclient python-keystoneclient python-novaclient python-quantumclient python-swiftclient quantum"
GITUSER="$USER"

if [ -z $1 ]; then
 echo "branch required (example: fuel/folsom)"
 exit 1
fi
branch=$1
#Find latest tag for release
#TODO: need to specify branch to get the latest tag that matches branch
lasttag=$(git describe --abbrev=0 --tags "openstack-ci/$branch")

if [ -z $2 ]; then
 #No release version specified, so we will create new based on the last one
 #Increment tag
 lastdigits=${lasttag##*[!0-9]}
 tag=${lasttag%$lastdigits}$((lastdigits+1))
 echo "New tag: $tag"
fi

#Make koji tags and set its parent to the previous tag
#Transforms fuel/2012.2.3/2.0.8 to 2012.2.3_fuel2.0.8 or 2012.2.3 to 
kojitag=$(echo $tag | awk -F'/' '(NF=3) { print $2"_"$1$3; } (NF=1) { print; }')
lastkojitag=$(echo $lasttag | awk -F'/' '(NF=3) { print $2"_"$1$3; } (NF=1) { print; }')
/usr/local/bin/make-tag.sh "$kojitag" "$lastkojitag"

#TODO: Mark $lasttag locked via `koji lock-tag $parenttag $parenttag-build

#Update openstack components in git
mkdir components
cd components
for component in components; do
  git clone ssh://$GITUSER@gerrit.mirantis.com:29418/openstack/$component.git
  cd $component
  git checkout -b localbranch remotes/origin/openstack-ci/$branch
  #TODO: nice fancy way?
  if grep -q client <<< $component;
    #New tag needs to be based on client version not openstack cycle
    #TODO: need to specify branch to get the latest tag that matches branch....
    lasttag=$(git describe --abbrev=0 --tags .... $branch)
    lasttaglastrelease=${lasttag##*[!0-9.]}
    newtag=${lasttag%$lastdigits}$((lasttaglastrelease+1))
    git tag "openstack-ci/$newtag"
  else
    git tag "openstack-ci/$tag"
    git review or git push?
  fi
done


  
