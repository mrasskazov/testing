class ca (
        $hub	             = 'koji.your-domain-name.com',
        $country             = 'US',
        $state               = 'California',
        $city                = 'Los Angeles',
        $organization        = 'Koji'
) {
         	

        file { "/etc/pki/koji/":
		ensure => directory,
        }
        file { "/etc/pki/koji/certs":
		ensure => directory,
        }
        file { "/etc/pki/koji/private":
		ensure => directory,
        }
        file { "/etc/pki/koji/confs":
		ensure => directory,
        }
	file { "/etc/pki/koji/ssl.cnf":
		ensure => present,
		source => 'puppet:///modules/ca/ssl.cnf',
		owner => root, group => root,
	}

        package { 'openssl':
                ensure => installed,
        }

#	file { "/etc/pki/tls/certs/590d426f.0":
#		ensure => link,
#		target => 'cacert-class3.crt',
#	}
        exec { "intialize_ca_index_txt":
        	command => "touch /etc/pki/koji/index.txt",
        	unless  => "test -f /etc/pki/koji/index.txt",
                path => '/usr/bin:/bin:/usr/sbin:/sbin',
                require => File["/etc/pki/koji"],
        }
        exec { "intialize_ca_serial":
        	command => "echo 01 > /etc/pki/koji/serial",
        	unless  => "test -f /etc/pki/koji/serial",
                path => '/usr/bin:/bin:/usr/sbin:/sbin',
                require => File["/etc/pki/koji"],
        }
        exec { "initialize_ca_key":
                command => "openssl genrsa -out /etc/pki/koji/private/koji_ca_cert.key 2048; \
                            openssl req -config /etc/pki/koji/ssl.cnf -new -x509 -days 7300 \
                              -subj \"/C=$country/ST=$state/L=$city/O=$organization/CN=$hub\" \
                              -key /etc/pki/koji/private/koji_ca_cert.key \
                              -out /etc/pki/koji/koji_ca_cert.crt -extensions v3_ca",
                unless => "test -f /etc/pki/koji/koji_ca_cert.crt",
                path => '/usr/bin:/bin:/usr/sbin:/sbin',
                require => File["/etc/pki/koji/ssl.cnf"],
        }


}
