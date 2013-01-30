class httpd {
	Class['iptables::webserver'] -> Class['httpd']

	package { 'httpd':
		ensure => installed
	}
	package { 'mod_ssl':
		ensure => installed
	}
	package { 'mod_python':
		ensure => installed
	}

	service { 'httpd':
		ensure => running,
		enable => true,
		hasstatus => true,
		hasrestart => true,
	}

        exec{ "permit_httpd_can_network_connect_db":
                command => "setsebool -P httpd_can_network_connect_db 1",
                onlyif => "bash -c \"getenforce && ( getsebool httpd_can_network_connect_db 2>&1 | grep -q off )\"",
                path => '/usr/bin:/bin:/usr/sbin:/sbin'
        }
}
