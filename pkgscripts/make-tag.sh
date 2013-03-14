#!/bin/bash
# make-tag.sh
# Generates a tag in koji which defines the following information:
# * A "build" tag where mock builds take place
# * Base packages required to begin installation
# * Yum repositories for OpenStack components, EPEL, and base CentOS packages
# * Assigns inheritance which allows new tags to automatically make use of the packages of its parent tag
# * Prepares mash config to make a yum repo of built packages

if [ -z "$1" ];then
  echo "Tag name required. Usage: $0 fuel-$tag"
  echo "Optionally add parent tag as second argument"
fi
#todo ensure only [a-z\-]*[a-z] pattern
tag="$1"
if [ -n "$2" ];then
  parenttag=$2
fi
#We don't need to copy epel/centos/etc repos every time. It wastes space and time.
if [[ $(koji list-external-repos --name=epel --quiet | wc -l) == 0 ]];then
  first="yes"
else
  first="no"
fi

echo "Setting up tag $tag..."
koji add-tag $tag 
koji add-tag --parent $tag --arches "x86_64" $tag-build
koji add-target $tag $tag-build

if [ -n "$parenttag" ];then
  koji add-tag-inheritance $tag $parenttag
  koji add-tag-inheritance $tag-build $parenttag-build
  #TODO: Mark $parrenttag locked via `koji lock-tag $parenttag $parenttag-build
else
  koji add-group $tag build
  koji add-group $tag-build build
  koji add-group-pkg $tag build bash buildsys-macros bzip2 coreutils cpio diffutils findutils gawk gcc\
   gcc-c++ grep gzip hwdata info initscripts make patch redhat-release redhat-rpm-config rpm-build sed\
   shadow-utils tar udev unzip useradd util-linux-ng which
koji add-group-pkg $tag-build build bash buildsys-macros bzip2 coreutils cpio diffutils findutils gawk\
   gcc gcc-c++ grep gzip hwdata info initscripts make patch redhat-release redhat-rpm-config rpm-build\
   sed shadow-utils tar udev unzip useradd util-linux-ng which

  koji add-group $tag srpm-build
  koji add-group $tag-build srpm-build
  koji add-group-pkg $tag srpm-build bash buildsys-macros bzip2 coreutils cpio diffutils findutils gawk\
   gcc gcc-c++ grep gzip hwdata info initscripts make patch redhat-release redhat-rpm-config rpm-build\
   sed shadow-utils tar udev unzip useradd util-linux-ng which
koji add-group-pkg $tag-build srpm-build bash buildsys-macros bzip2 coreutils cpio diffutils findutils\
   gawk gcc gcc-c++ grep gzip hwdata info initscripts make patch redhat-release redhat-rpm-config \
   rpm-build sed shadow-utils tar udev unzip useradd util-linux-ng which
fi

echo "Adding external yum repositories to tag $tag..."

if [[ "$first" == "yes" ]];then
  koji add-external-repo -t $tag-build "epel" "http://172.18.67.168/centos-repo/epel/"
else
  koji add-external-repo -t $tag-build "epel"
fi

if [[ "$first" == "yes" ]];then
# TODO: reroute this to the mash repo that this tag generates
# Like this: koji add-external-repo ... "$tag" "http://$ipaddress/$tag/x86_64/"
  koji add-external-repo -t $tag-build "fuel-folsom" "http://172.18.67.168/centos-repo/epel-fuel-folsom-stage/"
else
  koji add-external-repo -t $tag-build "fuel-folsom"
fi
# TODO: Figure out if we need to lock this down
if [[ "$first" == "yes" ]];then
  koji add-external-repo -t $tag-build "centos6.3-updates" "http://172.18.67.168/centos-repo/centos-6.3-updates/"
else
  koji add-external-repo -t $tag-build "centos6.3-updates"
fi

# TODO: Figure out if we need to lock this down per release
if [[ "$first" == "yes" ]];then
  koji add-external-repo -t $tag-build "centos63" "http://172.18.67.168/centos-repo/centos-6.3/"
else
  koji add-external-repo -t $tag-build "centos63"
fi


echo "Building repo data for $tag..."
koji regen-repo $tag-build &

echo "Generating mash config for $tag"
echo >> /etc/mash/koji.mash << EOF
[$tag]
rpm_path = %(arch)s/
repodata_path = %(arch)s/
source_path = source/SRPMS
debuginfo = True
multilib = True
multilib_method = devel
tag = $tag
inherit = True
strict_keys = False
keys = F8AF89DD

repoviewurl = http://osci-koji.srt.mirantis.net/mash/
repoviewtitle = "$tag - %(arch)s"
arches = x86_64
delta = True
# Change distro_tags as fedora-release version gets bumped
distro_tags = cpe:/o:CentOS:CentOS:6.3 $tag
hash_packages = False

EOF

