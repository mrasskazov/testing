class mash(
tags = {}) {
	package { 'mash':
		ensure => installed,
	}
        
	file { '/etc/mash/mash.conf':
		ensure => present,
		content => template('mash/mash.conf.erb'),
		require => Package['mash'],
	}
        file { '/etc/mash/koji.mash':
        	ensure  => present,
                content => template('mash/koji.mash.erb'),
                require => Package['mash'],
        }
}
