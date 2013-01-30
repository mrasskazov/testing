class ca::users (
        $hub           	     = 'koji.your-domain-name.com',
        $country             = 'US',
        $state               = 'California',
        $city                = 'Los Angeles',
        $organization        = 'Koji',
        $user_list           = 'kojiadmin kojihub kojiweb kojira koji.your-domain-name.com'
) {

        require ca         	

        $keypath = "/etc/pki/koji"
        $pkcs12pass = "koji"

        exec { "create_keys_for_user_list":
        	command => "bash -c \"for user in $user_list; do                    
                            if ! [ -f $keypath/certs/\\\$user.key ];then    
                              openssl genrsa -out $keypath/certs/\\\$user.key 2048
                            fi
                            done\"",
		unless  => "test -f $keypath/certs/kojiadmin.key",
                path => '/usr/bin:/bin:/usr/sbin:/sbin'

        }

        exec { "create_csrs_for_user_list":
        	command => "bash -c \"for user in $user_list; do                    
                            if ! [ -f $keypath/\\\$user.crt ];then    
                              openssl req                                 \
                                -config $keypath/ssl.cnf                  \
                                -new                                      \
                                -nodes                                    \
                                -subj \\\"/C=$country/ST=$state/L=$city/O=$organization/CN=\\\$user\\\"\
                                -out $keypath/certs/\\\$user.csr          \
                                -key $keypath/certs/\\\$user.key          \
                                -extensions v3_ca
                            fi
                            done\"",
		unless  => "test -f /etc/pki/koji/certs/kojiadmin.csr",
                path => '/usr/bin:/bin:/usr/sbin:/sbin',
                require => Exec["create_keys_for_user_list"]

        }

        exec { "sign_csrs_for_user_list":
        	command => "bash -c \"for user in $user_list; do
                            if ! [ -f $keypath/certs/\\\$user.crt ];then
                              yes | openssl ca                            \
                                -config $keypath/ssl.cnf                  \
                                -subj \\\"/C=$country/ST=$state/L=$city/O=$organization/CN=\\\$user\\\"\
                                -cert $keypath/koji_ca_cert.crt           \
                                -keyfile $keypath/private/koji_ca_cert.key\
                                -outdir $keypath/certs                    \
                                -out $keypath/certs/\\\$user.crt          \
                                -infiles $keypath/certs/\\\$user.csr
                            fi
                            done\"",
                cwd     => "/etc/pki/koji",
		unless  => "test -f /etc/pki/koji/certs/kojiadmin.crt",
                path => '/usr/bin:/bin:/usr/sbin:/sbin',
                require => Exec["create_csrs_for_user_list"]



        }

        exec { "combine_key_and_cert_for_user_list":
        	command => "bash -c \"for user in $user_list; do
                            if ! [ -f $keypath/\$user.pem ];then
                                cat certs/\\\$user.crt certs/\\\$user.key > \\\$user.pem
                            fi
                            done\"",
                cwd     => "/etc/pki/koji",
		unless  => "test -f /etc/pki/koji/kojiadmin.pem",
                path => '/usr/bin:/bin:/usr/sbin:/sbin',
                require => Exec["sign_csrs_for_user_list"]

        }

        exec { "generate_pkcs12_browser_cert_for_worker":
        	command => "echo $pkcs12pass | openssl pkcs12 -export \
                            -inkey certs/kojiadmin.key \
                            -in certs/kojiadmin.crt \
                            -CAfile koji_ca_cert.crt \
                            -password stdin \
                            -out certs/kojiadmin.p12",
                cwd     => "/etc/pki/koji",
		unless  => "test -f /etc/pki/koji/certs/kojiadmin.p12",
                path => '/usr/bin:/bin:/usr/sbin:/sbin',
                require => Exec["combine_key_and_cert_for_user_list"]

        }
}
