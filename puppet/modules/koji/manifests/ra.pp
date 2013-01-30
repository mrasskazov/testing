
class koji::ra($auth, $hub, $realm = 'NONE', worker = 'kojiadmin') {
	package { 'koji-utils': ensure => installed }
	package { 'repoview': ensure => installed }
        exec { 'worker_can_connect':
         	command => "su - $worker -c \"koji list-permissions --mine\"",
                path => '/usr/bin:/bin:/usr/sbin:/sbin',
        }   
        exec { 'add_kojira_user_manually':
        	#command => 'koji add-user kojira',
        	command => "su - $worker -c \"koji add-user kojira && koji grant-permission repo kojira\"",
                path => '/usr/bin:/bin:/usr/sbin:/sbin',
                unless => "su - $worker -c \"koji list-permissions --user=kojira 2>&1 | grep -q repo\"",
                require => Exec['worker_can_connect']
        }

	service { 'kojira':
		ensure => running,
		enable => true,
		hasstatus => true,
		hasrestart => true,
		require => Package['koji-utils'],
	}
	file { '/etc/kojira/kojira.conf':
		ensure => present,
		content => template('koji/ra/kojira.conf.erb'),
		notify => Service['kojira'],
		require => Package['koji-utils'],
	}
	# Link to Koji-hub's CA, so kojira can properly verify it.
	file { '/etc/kojira/kojihubca.crt':
		ensure => link,
		target => '/etc/pki/tls/certs/cacert-class3.crt',
		require => Package['koji-builder'],
	}
	case $auth {
		kerberos: {
			if( $realm == 'NONE' ) {
				fail('If you use Kerberos authentication, you must specify a $realm.')
			}
			class {'koji::ra::kerberos': }
		}
		ssl: { 
                        class {'koji::ra::ssl': }
                }
		default: { fail('Unrecognized auth type for DB.') }
	}
}

class koji::ra::kerberos {
	# Kojira's keytab.
	file { '/etc/kojira/kojira.keytab':
		ensure => present,
		owner => 'root', group => 'root',
		mode => '640',
		notify => Service['kojira'],
		require => Package['koji-utils'],
	}
}
class koji::ra::ssl {
        # Kojira's key.
        file { '/etc/kojira/client.crt':
                ensure => link,
                target => "/etc/pki/koji/kojira.pem",
                notify => Service['kojira'],
                require => Package['koji-utils'],
        }
        file { '/etc/kojira/clientca.crt':
                ensure => link,
                target => "/etc/pki/koji/koji_ca_cert.crt",
                notify => Service['kojira'],
                require => Package['koji-utils'],
        }
        file { '/etc/kojira/serverca.crt':
                ensure => link,
                target => "/etc/pki/koji/koji_ca_cert.crt",
                notify => Service['kojira'],
                require => Package['koji-utils'],
        }
}

