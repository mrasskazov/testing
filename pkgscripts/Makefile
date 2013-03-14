### Package information
ifneq "$(MAKECMDGOALS)" "clean"
  ifeq "${name}" ""
  #Fail unless make clean was run
    $(error Run make name=COMPONENT. (Example: make name=nova))
  endif
endif

ifndef ${specfile}
  specfile=$(shell ls -1 rpm/SPECS/*.spec | head -1)
endif

ifndef ${GITUSER}
  GITUSER=openstack-ci-jenkins
endif

ifndef ${branch}
  #Default branch is folsom
  branch=folsom
endif


#Tag here refers to which Koji release tag, not component milestone
#fuel/folsom will be fuel-folsom, for example
tag=$(shell echo -en "${branch}" | tr '/' '-')

#Parse RPM package name from specfile
rpmname=$(shell rpm -q --qf '%{name}\n' --specfile ${specfile} | head -1)
os=$(shell if [ -f "/etc/redhat-release" ]; then echo redhat; elif [ -f "/etc/debian_version" ]; then echo ubuntu; fi)

#Save branch name where this build is so we can refer to it later
buildbranch=$(shell git rev-parse --abbrev-ref HEAD)
#Extract version tag if set
ifeq "${os}" "redhat"
  version=$(shell git describe --tags remotes/origin/openstack-ci/${branch} | awk -F'/' '(NF == 4) { print $$3"."$$2$$4; } (NF == 2) { print $$2; }')
else
  version=$(shell git describe --tags remotes/origin/openstack-ci/${branch} | awk -F'/' '(NF == 4) { print $$3"."$$2$$4; } (NF == 2) { print $$2; }')
endif
ifeq "${version}" ""
  #Default version is 2012.2.3
  version=2012.2.3
endif

#changelog information
author=$(shell git log remotes/origin/openstack-ci/${branch} -n 1 | grep Author: | cut -c9-)
date=$(shell git log remotes/origin/openstack-ci/${branch} -n 1 | grep Date: | cut -d' ' -f4,5,6,8)
message=$(shell git log remotes/origin/openstack-ci/${branch} -n 1 | tail -n +5 | tr '"' "'")

patches=
ifneq ($(shell (test -d patches && find patches -type f) | wc -l),0)
  patches=preppatches
endif

.PHONY: print_vars

all: rpm koji

changelog:
	/usr/bin/rpmdev-bumpspec -c "${message}" -u "Mirantis OSCI <product@mirantis.com>" -r ${specfile}

clean:
	rm -rf rpm/BUILDROOT/ *.deb *.src.rpm


rpm: ${patches} version changelog tarball
	rpmbuild --define "_topdir rpm/" \
--define "_builddir /tmp" \
--define "_srcrpmdir ${PWD}" \
--define "_specdir %{_topdir}/SPECS" \
--define "_sourcedir %{_topdir}/SOURCES" \
-bs ${specfile}


koji:
	#Ensure package is in koji approved packages for ${tag}
	if ! koji list-pkgs --tag=${tag} --package=${rpmname} --quiet; then \
	  koji add-pkg --owner $${USER} ${tag} ${rpmname};\
	fi
	#Outputs task information to taskinfo so it can be parsed
	koji build ${tag} ${rpmname}*.src.rpm  --noprogress --nowait | tee taskinfo

preppatches:
	#Skip if no patches
	#Copy patches to SOURCES
	cp -f ./patches/* rpm/SOURCES/
	for patch in patches/*; do \
	  patch=`basename $$patch`;\
	  if grep -q "$${patch}" ${specfile}; then \
	    patchnum=`grep "$${patch}" ${specfile} | cut -d':' -f1 | cut -c6-`; \
	  else \
	    highest=-1; \
	    for patchno in `egrep 'Patch.*:' ${specfile} | cut -d':' -f1 | cut -c6-`; do \
	      if [[ $${patchno} > $${highest} ]];then \
	        highest=$${patchno};\
	      fi;\
	    done;\
	    (( patchnum = highest + 1 ));\
	    printf '%s\n' '?^Patch?a' "Patch$${patchnum}: $$patch" . w | ed -s ${specfile};\
	  fi;\
	  if ! grep -q "%patch$${patchnum}" ${specfile}; then \
	    if grep -q "%patch" ${specfile}; then \
	      printf '%s\n' '?%patch?a' "%patch$${patchnum} -p1" . w | ed -s ${specfile};\
	    else \
	      echo "Spec file doesn't define any patches. Unable to continue. Do patches manually."; \
	      exit 1; \
	    fi;\
	  fi;\
	done



rpm-test:
	rpmlint -i *.rpm *.spec

tarball:
	#git archive --format=tar --prefix=${name}-${version}/ remotes/origin/openstack-ci/${branch} | gzip > rpm/SOURCES/${name}-${version}.tar.gz
	#Commit any changes
	git commit -a -m 'build updates'
	#Check out code branch 
	git checkout -b ${branch} "remotes/origin/openstack-ci/${branch}"
	git tag ${version}
	sed -i 's/version=.*$$/version="${version}",/' setup.py
	python setup.py sdist -d ../
	#Discard and return
	git reset --hard HEAD
	git checkout ${buildbranch}
	#Move tarball into rpm sources
	mkdir -p rpm/SOURCES/
	mv ../${name}-${version}.tar.gz rpm/SOURCES/

version:
	#Get latest build from koji. If it fails, it's okay and we reset release to mira.1
	#Then update the release and version in spec file
	koji download-build --latestfrom=${tag} ${rpmname} --arch=src || :
	#See if version is the same as last build. If the same, set same release (will be incremented later)
	if [[ "`rpm -qp --qf '%{version}' ${rpmname}*.src.rpm`" == "${version}" ]];then\
	  release="`rpm -qp --qf '%{release}' ${rpmname}*.src.rpm`";\
	else \
	  release="mira.1";\
	fi;\
	rm -f ${rpmname}*.src.rpm;\
	sed -i "s/Version:.*$$/Version:          ${version}/" ${specfile};\
	sed -i "s/Release:.*$$/Release:          $${release}/" ${specfile};\

deb:
	#Make an "upstream branch" with folsom + build/folsom's debian folder
	git checkout -b upstream "remotes/origin/openstack-ci/${branch}"
	#Prepare source branch
	git checkout -b ${branch} "remotes/origin/openstack-ci/${branch}"
	#Make tag with %{version}
	if ! git tag --list | grep -q ${version}; then\
	  git tag ${version};\
	fi
	#Add debian folder from build branch
	git checkout ${buildbranch} debian
	rm -rf /tmp/ddd
	mkdir -p /tmp/ddd
	cp -r debian /tmp/ddd
	rm -rf /tmp/ddd/debian/patches
	git checkout -b buildone ${version}
	cp -r /tmp/ddd/debian .
	git add debian/*
	#git-dch --full -R --debian-branch=buildone -s "${version}" --spawn-editor=none
	#git-dch --full -S --debian-branch=buildone --spawn-editor=none -s "${version}" -N "${version}"
	git-dch --full -R --debian-branch=buildone -s "${version}" --spawn-editor=none  -N "${version}"
	#TODO: Replace with actual message
	git commit -a -m "Changelog for version ${branch}"
	git-buildpackage --git-dist=precise --git-debian-branch=buildone --git-upstream-branch=upstream --git-upstream-tree=branch --git-force-create --git-pbuilder --git-ignore-new

print_vars:
	echo ${version}

