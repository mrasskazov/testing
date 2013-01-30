
class koji::worker($auth, $hub, $allowed_scms, $worker = 'kojiadmin' ) {

	package { 'koji':
		ensure => installed,
	}

	user {  $worker:
		ensure => present,
                managehome => true,
	}
        file { "/etc/koji.conf":
                content => template('koji/worker/koji.conf.erb'),
                require => Package['koji']
        }

	case $auth {
		kerberos: {
			if( $realm == 'NONE' ) {
				fail('If you use Kerberos authentication, you must specify a $realm.')
			}
			class {'koji::worker::kerberos': }
		}
		ssl: { 
                        class {'koji::worker::ssl': 
				require => User[$worker],
                        } 
                         
                }
		default: { fail('Unrecognized auth type.') }
	}
}

class koji::worker::kerberos {
	# worker's keytab.
	file { "/etc/kojid/$worker.keytab":
		ensure => present,
		owner => 'root', group => $worker,
		mode => '640',
		notify => Service['kojid'],
		require => Package['koji'],
	}
	# Link to Koji-hub's CA, so kojid can properly verify it.
	file { '/etc/kojid/kojihubca.crt':
		ensure => link,
		target => '/etc/pki/tls/certs/cacert-class3.crt',
		require => Package['koji'],
	}

}

class koji::worker::ssl {
	# worker's key.
	file { "/home/$worker/.koji/":
		ensure => directory,
                owner => $worker, group => $worker,
        }
	file { "/home/$worker/.koji/client.crt":
		ensure => link,
		target => "/etc/pki/koji/$worker.pem",
		require => Package['koji'],
	}
	file { "/home/$worker/.koji/clientca.crt":
		ensure => link,
		target => "/etc/pki/koji/koji_ca_cert.crt",
		require => Package['koji'],
	}
	file { "/home/$worker/.koji/serverca.crt":
		ensure => link,
		target => "/etc/pki/koji/koji_ca_cert.crt",
		require => Package['koji'],
	}
        

}
# Use this class if the worker will access the SCM over SSH
class koji::worker::ssh {
	# Worker runs SCM command as root. Put SSH keys here if using an SCM over SSH.
	file { "/home/$worker/.ssh":
		ensure => directory,
		mode => '700',
		owner => 'root', group => 'root',
	}
	# Worker's private key
	file { "/home/$worker/.ssh/id_rsa":
		mode => '600',
		owner => 'root', group => 'root',
	}
	# SCM Host's public key
	sshkey { 'cvs.rpmfusion.org':
		ensure => present,
		key => 'AAAAB3NzaC1yc2EAAAABIwAAAQEAxQVhR8gzsWoY6ghHP+jqnMve6YZwsFbVhYYCQ1O5kYR8lwlmIXJZ9u0B0kvdU4SONjQe11OX8xihrwPei5Xcj2kEhTQFkeTsRR5ApbawMcmWyhwTeuUsiTd76CqNj/cEossc0wAqsVhZg397vDxrckxVLSpP2dCuHL4P4LP4clbc+rYKP7nnSL+ngBSQRSm+0UQhZu37KXb5tB3nSTsph6anzlTYIiTM6i29ShunNOGzeFwp7y7ospMmKhWZnfWjKA/O7IXYCYxb9gr/69cv8Q3IsRfMMhxxUnBbWLUQb4w5CZPhXFRtBr3hJcHDAWNISu0b19oQOXvmY6yZKa2pYw==',
		type => 'ssh-rsa',
	}
}

