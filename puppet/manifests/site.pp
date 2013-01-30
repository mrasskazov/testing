#### This manifest file configures a single-node Koji server which relies on
#### SSL certificate authentication

#General
$server              = 'koji-osci'
$domain_name         = 'vm.mirantis.net'
$hub		     = "$server.$domain_name"
$arch                = "x86_64"
$allowed_scms        = "git.*:*"
#git info
$gituser	     = 'koji'

#SSL CA information
$country             = 'US'
$state               = 'California'
$city                = 'Los Angeles'
$organization        = 'Koji'

#Koji users
$kojiusers           = "kojiadmin kojihub kojiweb kojira $hub"
$worker		     = "kojiadmin"

#Tags we will build
$tags = {
  'folsom' => { 
	gitrepo => "ssh://$gituser@gerrit.mirantis.com:29418/fuel/epel-fuel.git",
        gpgkeys => "",
  },
  'grizzly' => {
	gitrepo => "ssh://$gituser@gerrit.mirantis.com:29418/openstack-ci/grizzly.git",
        gpgkeys => "",
  }
}

#Yum repositories with all dependencies:
$repos = {
	'centos6.3-updates'       => 'http://172.18.67.168/centos-repo/centos-6.3-updates/',
	'centos63'                => 'http://172.18.67.168/centos-repo/centos-6.3/',
	'epel'                    => 'http://172.18.67.168/centos-repo/epel/',
	'fuel-folsom'             => 'http://172.18.67.168/centos-repo/epel-fuel-folsom-stage/'
} 

#Base packages needed to set up core build environment
$basepkgs = 'bash buildsys-macros bzip2 coreutils cpio diffutils findutils gawk gcc gcc-c++ grep gzip hwdata info initscripts make patch redhat-release redhat-rpm-config rpm-build sed shadow-utils tar udev unzip useradd util-linux-ng which'

stage { 'epel': before => Stage['main'] }
class { 'repos::epel': stage => 'epel' }

stage { 'ca': before => Stage['main'] }

# For simplicity, this one server will just do everything.
#node "osci-koji.srt.mirantis.net" {
node /koji/ {
        
	# System CA configuration.
	class {'ca':
		hub		=> $hub,
                country		=> $country,
                state 		=> $state,
                city 		=> $city,
                organization 	=> $organization,
                stage		=> 'ca'
	}
	class {'ca::users':
		hub		=> $hub,
                country		=> $country,
                state 		=> $state,
                city 		=> $city,
                organization 	=> $organization,
                user_list	=> $kojiusers,
                stage		=> 'ca',
                require => Class['ca']
	}

         
	# Postgresql server.
	class {'koji::db':
		# bootstrap this user.
		user => $worker,
		auth => 'ssl',
                require => Class['ca::users'],
	}

	# Dependencies for koji::hub
	class {'httpd': }
	class {'iptables::webserver': }
	class {'cacert': }

	# Koji-Hub software.
	class {'koji::hub':
		auth => 'ssl',
		db => '127.0.0.1',
		hub => $hub,
                require => Class['koji::db']
	}

	# Koji-Web software.
	class {'koji::web':
		auth => 'ssl',
		hub => $hub,
                require => Class['koji::hub']
	}

	# Kojid software.
	class {'koji::builder':
		auth => 'ssl',
		hub => $hub,
		allowed_scms => $allowed_scms,
                require => Class['koji::hub','httpd']
	}
	class {'koji::worker':
		auth => 'ssl',
		hub => $hub,
		allowed_scms => '*:/*:rpms',
                worker => $worker,
                require => Class['koji::hub','httpd']
	}

	# SCM uses SSH
	class {'koji::builder::ssh': }
        #Add build host to build system list
        class {'koji::builder::addhost':
                host => $hub,
                worker => $worker,
                arch => $arch,
                require => Class['koji::worker'],
        }

	class {'koji::ra':
		auth => 'ssl',
		hub => $hub,
                worker => $worker,
                require => Class['koji::worker']
	}

        class {'build::tags':
                worker          => $worker,
                tags		=> $tags,
                basepkgs	=> $basepkgs,
                repos		=> $repos,
         }
                

        class { mash: tags => $tags}

        #Next Steps:
        #Define tags we want: folsom folsom-dell grizzly.. etc
        #Set up base group pkgs:
        #build  [fuel-folsom]  bash  buildsys-macros  bzip2  coreutils  cpio  diffutils  findutils    gawk  gcc  gcc-c++  grep  gzip  hwdata  info  initscripts  make  patch  python-websockify  redhat-release  redhat-rpm-config  rpm-build  sed  shadow-utils  tar  udev  unzip  useradd  util-linux-ng  which
        #srpm-build  [fuel-folsom] bash  buildsys-macros  bzip2  coreutils  cpio  curl  cvs  diffutils  gawk  gcc  gcc-c+  gnupg  grep  gzip  hwdata  info  initscripts  make  patch  python-websockify  redhat-release  redhat-rpm-config  rpm-build  sed  shadow-utils  tar  udev  unzip  useradd  util-linux-ng  which
        #Add yum repos to use to build from
          #Consider local mirror for client OR squid proxy
          #Need these for Fuel:
          #$ koji list-external-repos --tag=fuel-folsom
          #Pri External repo name        URL
          #--- ------------------------- ----------------------------------------
          #5   centos6.3-updates         http://172.18.67.168/centos-repo/centos-6.3-updates/
          #10  centos63                  http://172.18.67.168/centos-repo/centos-6.3/
          #15  epel                      http://172.18.67.168/centos-repo/epel/
          #20  fuel-folsom               http://172.18.67.168/centos-repo/epel-fuel-folsom-stage/

        #Use command koji add-group-pkg fuel-folsom [build|srpm-build] pkgname [pkgname2]
        #Mash (repo setup)
        #RPM signing automation (generate gpg key if needed)
        #Set up worker account (kojiadmin) to hook into git repos specified, add them to its mechanics, and watch for updates? OR we just let jenkins do this and teach koji how to do this smartly:
          ##For example:
          #jenkins checks out the code and scps the entire repo to /home/kojiadmin/build/
          #`make srpm` is run. Makefile points to spec file, sources, patches, etc, and outputs to /tmp/pkgname-XXXXXX
          #kojiadmin runs koji build TAGNAME /tmp/pkgname-XXXXXX/pkgname-version.src.rpm
        #Spec updating for patches and release needed in any case for universal solution
	#Methods to consider:
        #./pkgname/SOURCES/*.patch
        #./pkgname/PATCHES/*
        #./other-git-repo/*
 
}
