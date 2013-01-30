
class krb5($realm, $admin_server = 'NONE') {
	package { 'krb5-workstation':
		ensure => installed,
	}
	file { '/etc/krb5.conf':
		content => template('krb5/krb5.conf.erb'),
		require => Package['krb5-workstation'],
	}
}
