
class cacert {
	# Install CACert.org CA.

	# From https://secure.cacert.org/certs/class3.txt
	file { "/etc/pki/tls/certs/cacert-class3.crt":
		ensure => present,
		source => 'puppet:///modules/cacert/class3.txt',
		owner => root, group => root,
	}
	file { "/etc/pki/tls/certs/590d426f.0":
		ensure => link,
		target => 'cacert-class3.crt',
	}
}
