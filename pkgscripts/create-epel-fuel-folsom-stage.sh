#!/bin/bash
cd /usr/src/repo/epel-fuel-folsom-stage
#Sync repos
yum --enablerepo='fuel-epel-mash' --enablerepo='fuel-epel-mash-source' clean expire-cache
reposync -r fuel-epel-mash -c /etc/yum/yum.conf -p /usr/src/repo/epel-fuel-folsom-stage/ --norepopath -d
#Make subfolders
mkdir -p SRPMS x86_64 noarch
reposync -r fuel-epel-mash-source --source -c /etc/yum/yum.conf -p /usr/src/repo/epel-fuel-folsom-stage/SRPMS --norepopath
#Move rpms into subfolders
mv *.x86_64.rpm x86_64
mv *.noarch.rpm noarch
createrepo /usr/src/repo/epel-fuel-folsom-stage/

