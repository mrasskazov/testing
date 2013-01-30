class build::tags( $tags = {}, $repos = {}, $basepkgs, $worker = 'kojiadmin' ) {


        file { "/usr/local/bin/create_tags.sh":
               content => template("build/create_tags.sh.erb"),
               ensure => file,
               owner => 'root', group => 'root',
               mode => '755',
               notify => Exec["create_tags"],
        }
	exec { "create_tags":
        	command => "su - $worker -c '/usr/local/bin/create_tags.sh'",
                path => '/usr/bin:/bin:/usr/sbin:/sbin',
                require => Exec['worker_can_connect']
        }
}


