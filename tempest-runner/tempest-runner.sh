#!/bin/bash -x

TOS_REINSTALL_VIRTUALENV=${TOS_REINSTALL_VIRTUALENV:-false}
TOS_CREATE_ENTITIES=${TOS_CREATE_ENTITIES:-true}
TOS_DELETE_ENTITIES=${TOS_DELETE_ENTITIES:-false}

TESTCASE=${TESTCASE:-tempest/tests}
OS_USERNAME=${OS_USERNAME:-admin}
OS_PASSWORD=${OS_PASSWORD:-secrete}
OS_TENANT_NAME=${OS_TENANT_NAME:-admin}
OS_AUTH_STRATEGY=${OS_AUTH_STRATEGY:-keystone}

TOS_IMAGE_NAME=${TOS_IMAGE_NAME:-tempest-cirros-01}

CIRROS_HOST=http://download.cirros-cloud.net/
wget -c $CIRROS_HOST/version/released
CIRROS_RELEASE=$(cat released)
rm released
TOS_IMAGE_LINK=${TOS_IMAGE_LINK:-"http://download.cirros-cloud.net/$CIRROS_RELEASE/cirros-$CIRROS_RELEASE-x86_64-disk.img"}

TOS_IMAGE_NAME_ALT=${TOS_IMAGE_NAME_ALT:-tempest-cirros-02}
TOS_IMAGE_LINK_ALT=${TOS_IMAGE_LINK_ALT:-$TOS_IMAGE_LINK}

TOS_FLAVOR_REF=${TOS_FLAVOR_REF:-641}
TOS_FLAVOR_REF_ALT=${TOS_FLAVOR_REF_ALT:-642}

TOS_MEMBER_ROLE_NAME=${TOS_MEMBER_ROLE_NAME:-Member}

TOS_USERNAME=${TOS_USERNAME:-u1}
TOS_PASSWORD=${TOS_PASSWORD:-secrete}
TOS_TENANT_NAME=${TOS_TENANT_NAME:-t1}

TOS_USERNAME_ALT=${TOS_USERNAME_ALT:-u2}
TOS_PASSWORD_ALT=${TOS_PASSWORD_ALT:-secrete}
TOS_TENANT_NAME_ALT=${TOS_TENANT_NAME_ALT:-t2}

TOS_PATH_TO_PRIVATE_KEY=${TOS_PATH_TO_PRIVATE_KEY:-/var/lib/puppet/ssh_keys/openstack}
TOS_DB_HA_HOST=${TOS_DB_HA_HOST:-localhost}
TOS_DB_URI=${TOS_DB_URI:-mysql://nova:nova@$TOS_DB_HA_HOST/nova}

TOS_RUN_SSH=${TOS_RUN_SSH:-false}
TOS_SSH_USER=${TOS_SSH_USER:-cirros}
TOS_NETWORK_FOR_SSH=${TOS_NETWORK_FOR_SSH:-t1_router_net}
TOS_IP_VERSION_FOR_SSH=${TOS_IP_VERSION_FOR_SSH:-4}


TOS__NETWORK__API_VERSION=${TOS__NETWORK__API_VERSION:-v2.0}


TOP_DIR=$(cd $(dirname "$0") && pwd)
TEMPEST_DIR=$(readlink -f $TOP_DIR/../../tempest)
if [[ ! -r $TEMPEST_DIR ]]; then
    echo "ERROR: missing tempest dir $TEMPEST_DIR"
    exit 1
fi

if [ -z $OS_AUTH_URL ]; then
    echo 'ERROR: Missing $OS_AUTH_URL variable'
    exit 2
fi
TOS_HOST=$(echo $OS_AUTH_URL | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}')
TOS_PORT=$(echo $OS_AUTH_URL | grep -Eo ':([0-9]{1,5})' | cut -d ":" -f2)
TOS_API_VERSION=$(echo $OS_AUTH_URL | grep -Eo 'v([0-9\.])+')


change_value () {
    FILENAME=$1
    SECTION=$2
    PARAM=$3
    VALUE=$4
    if [ "$SECTION" == "__ANY__" ]; then
        # change all the matching
        sed -i -e "s|\(^$PARAM\s=\).*|\1 $VALUE|" $FILENAME
    else
        # change only in '$SECTION'
        sed -ine "/^\[$SECTION\].*/,/^$PARAM\s=.*/ s|\(^$PARAM\s=\).*|\1 $VALUE|" $FILENAME
    fi
}

get_obj_id () {
    echo $($@ | awk '/ id / { print $4 }')
}

get_id () {
    # object_name command with parameters
    # get_id t1 keystone tenant_list
    PARAM_NAME=$1
    shift
    echo $($@ | awk '/ '$PARAM_NAME' / { print $2 }')
}

tenant_create () {
    # tenant_name
    if [ "$(get_id $1 keystone tenant-list)" == "" ]; then
        keystone --debug tenant-create --name $1 || exit 1
        echo $?
    fi
}
user_create () {
    # user_name tenant_name password email enabled
    if [ "$(get_id $1 keystone user-list)" == "" ]; then
        keystone --debug user-create --name $1 --tenant-id $(get_id $2 keystone tenant-list) --pass $3 --email $4 --enabled $5 || exit 1
        echo $?
    fi
}
user_role_add () {
    # user_name tenant_name role_name
    if [ "$(get_id $3 keystone role-list)" != "" ]; then
        if [ "$(keystone user-role-list --user-id $(get_id $1 keystone user-list) --tenant-id $(get_id $2 keystone tenant-list) | grep '^| [a-z0-9]' | grep -vi ' id ')" == "" ]; then
            keystone --debug user-role-add --user-id $(get_id $1 keystone user-list) --tenant-id $(get_id $2 keystone tenant-list) --role-id $(get_id $3 keystone role-list) || exit 1
            echo $?
        fi
    else
        echo "Wrong system variable value: \$TOS_MEMBER_ROLE_NAME=$TOS_MEMBER_ROLE_NAME"
    fi
}
flavor_create () {
    # is_public flavor_name id ram disk vcpus
    if [ "$(get_id $2 nova flavor-list)" == "" ]; then
        nova --debug flavor-create --is-public $1 $2 $3 $4 $5 $6
        echo $?
    fi
}
image_create_img () {
    # is-public name IMANE_LINK disk-format container-format
    if [ "$(get_id $2 glance image-list)" == "" ]; then
        wget --progress=dot:mega -c $3
        TOS_IMAGE_FILE_NAME=.$(echo $3 | grep -Eo '/[^/]*?$')
        glance --debug image-create --is-public $1 --name $2 --file $TOS_IMAGE_FILE_NAME --disk-format $4 --container-format $5 || exit 1
        echo $?
    fi
}
net_create () {
    # tenant_name sip_lease gateway eg_id net_type ip_version router_name net_name subnet_name
    # if [ "$(get_id $2 glance image-list)" == "" ]; then
    TENANT_ID=$(get_id $1 keystone tenant-list)
    IP_LEASE=${2:-10.0.1.0/24}
    DEF_GATEWAY=$(echo $(echo $IP_LEASE | grep -Eo '([0-9]{1,3}\.){3}')1)
    GATEWAY=${3:-$DEF_GATEWAY}
    MAX_SEG_ID=$(for n in $(quantum net-list | grep '^| [a-z0-9]' | grep -v ' id ' | awk '{print $2}'); do quantum net-show $n | awk '/segmentation_id/ {print $4}'; done | sort -g | tail -n1)
    SEG_ID=${4:-$(($MAX_SEG_ID + 1))}
    CUR_NET_TYPE=$(quantum net-show $(quantum net-list | grep '^| [a-z0-9]' | grep -vi ' id ' | tail -n1 | awk '{print $2}') | awk '/network_type/ {print $4}')
    NET_TYPE=${5:-$CUR_NET_TYPE}
    CUR_IP_VERSION=$(quantum subnet-show $(quantum subnet-list | grep '^| [a-z0-9]' | grep -vi ' id ' | tail -n1 | awk '{print $2}') | awk '/ip_version/ {print $4}')
    IP_VERSION=${6:-$CUR_IP_VERSION}
    ROUTER_NAME=${7:-$1_router}
    NET_NAME=${8:-${ROUTER_NAME}_net}
    SUBNET_NAME=${9:-sub_${NET_NAME}}

    if [ "$(get_id $NET_NAME quantum net-list)" == "" ]; then
        quantum net-create --tenant_id $TENANT_ID $NET_NAME --provider:network_type $NET_TYPE --provider:segmentation_id $SEG_ID || exit 1
    fi
    NET_ID=$(get_id $NET_NAME quantum net-list)

    if [ "$(get_id $SUBNET_NAME quantum subnet-list)" == "" ]; then
        quantum subnet-create --name sub_$NET_NAME --tenant_id $TENANT_ID --ip_version $IP_VERSION $NET_ID --gateway $GATEWAY $IP_LEASE || exit 1
    fi
    SUBNET_ID=$(get_id $SUBNET_NAME quantum subnet-list)

    if [ "$(get_id $ROUTER_NAME quantum router-list)" == "" ]; then
        quantum router-create --tenant_id $TENANT_ID $ROUTER_NAME || exit 1
    fi
    ROUTER_ID=$(get_id $ROUTER_NAME quantum router-list)

    quantum router-interface-add ${ROUTER_ID} ${SUBNET_ID}

    # for external network
    #quantum router-gateway-set --request-format json $ROUTER_ID $NET_ID
}
net_delete () {
    # tenant_name router_name net_name subnet_name
    # if [ "$(get_id $2 glance image-list)" == "" ]; then
    TENANT_ID=$(get_id $1 keystone tenant-list)
    ROUTER_NAME=${2:-$1_router}
    NET_NAME=${3:-${ROUTER_NAME}_net}
    SUBNET_NAME=${4:-sub_${NET_NAME}}

    ### EMERGENCY CLEANING ###
    # for r in $(quantum router-list | awk '/t[12]_router/ {print $2}'); do for sn in $(quantum subnet-list | awk '/_net/ {print $2}'); do quantum router-interface-delete $r $sn; done; done
    # quantum subnet-list | awk '/_net/ {print $2}' | xargs -n1 -i% quantum subnet-delete %
    # quantum net-list | awk '/_net/ {print $2}' | xargs -n1 -i% quantum net-delete %
    # quantum router-list | awk '/t[12]_router/ {print $2}' | xargs -n1 -i% quantum router-delete %

    quantum router-interface-delete $(get_id $ROUTER_NAME quantum router-list) $(get_id $SUBNET_NAME quantum subnet-list)
    quantum subnet-delete $(get_id $SUBNET_NAME quantum subnet-list)
    quantum net-delete $(get_id $NET_NAME quantum net-list)
    quantum router-delete $(get_id $ROUTER_NAME quantum router-list)
}


pushd $TEMPEST_DIR
    echo "================================================================================="
    route -n
    echo "================================================================================="
    find . -name *.pyc -delete
    if [ "$TOS_REINSTALL_VIRTUALENV" = "true" ]; then
        rm -rf .tempest_venv
    fi
    virtualenv .tempest_venv
    . .tempest_venv/bin/activate
    pip install -r tools/pip-requires || exit 1
    pip install -r tools/test-requires || exit 1
    pip install -r $TOP_DIR/tempest-runner-pre-requires || exit 1
    pip install -r $TOP_DIR/tempest-runner-requires || exit 1

    if [ "$TOS_CREATE_ENTITIES" = "true" ]; then
        echo "================================================================================="
        echo "Preparing Tempest's environment..."

        tenant_create $TOS_TENANT_NAME
        user_create $TOS_USERNAME $TOS_TENANT_NAME $TOS_PASSWORD $TOS_USERNAME@$TOS_TENANT_NAME.qa true
        user_role_add $TOS_USERNAME $TOS_TENANT_NAME $TOS_MEMBER_ROLE_NAME
        net_create $TOS_TENANT_NAME 10.0.1.0/24

        tenant_create $TOS_TENANT_NAME_ALT
        user_create $TOS_USERNAME_ALT $TOS_TENANT_NAME_ALT $TOS_PASSWORD_ALT $TOS_USERNAME_ALT@$TOS_TENANT_NAME_ALT.qa true
        user_role_add $TOS_USERNAME_ALT $TOS_TENANT_NAME_ALT $TOS_MEMBER_ROLE_NAME
        net_create $TOS_TENANT_NAME_ALT 10.0.2.0/24

        flavor_create true f64_1 $TOS_FLAVOR_REF 64 0 1
        flavor_create true f64_2 $TOS_FLAVOR_REF_ALT 64 0 1

        # is-public name disk-format IMAGE_LINK container-format
        image_create_img true $TOS_IMAGE_NAME $TOS_IMAGE_LINK qcow2 bare
        image_create_img true $TOS_IMAGE_NAME_ALT $TOS_IMAGE_LINK qcow2 bare

    fi

    echo "================================================================================="
    echo "Generating Tempest's config..."
    pushd etc
        ORIG=tempest.conf.sample
        CONF=tempest.conf
        cp -f $ORIG $CONF

        change_value $CONF __ANY__ host $TOS_HOST
        change_value $CONF identity port $TOS_PORT
        change_value $CONF identity api_version $TOS_API_VERSION
        change_value $CONF identity strategy $OS_AUTH_STRATEGY

        change_value $CONF __ANY__ image_ref $(get_id $TOS_IMAGE_NAME glance image-list)
        change_value $CONF __ANY__ image_ref_alt $(get_id $TOS_IMAGE_NAME_ALT glance image-list)
        change_value $CONF __ANY__ flavor_ref $TOS_FLAVOR_REF
        change_value $CONF __ANY__ flavor_ref_alt $TOS_FLAVOR_REF_ALT

        change_value $CONF compute username $TOS_USERNAME
        change_value $CONF compute password $TOS_PASSWORD
        change_value $CONF compute tenant_name $TOS_TENANT_NAME

        change_value $CONF compute alt_username $TOS_USERNAME_ALT
        change_value $CONF compute alt_password $TOS_PASSWORD_ALT
        change_value $CONF compute alt_tenant_name $TOS_TENANT_NAME_ALT

        change_value $CONF compute path_to_private_key $TOS_PATH_TO_PRIVATE_KEY
        change_value $CONF compute db_uri $TOS_DB_URI

        change_value $CONF compute run_ssh $TOS_RUN_SSH
        change_value $CONF compute ssh_user $TOS_SSH_USER
        change_value $CONF compute network_for_ssh $TOS_NETWORK_FOR_SSH
        change_value $CONF compute ip_version_for_ssh $TOS_IP_VERSION_FOR_SSH

        change_value $CONF image username $TOS_USERNAME
        change_value $CONF image password $TOS_PASSWORD
        change_value $CONF image tenant_name $TOS_TENANT_NAME

        change_value $CONF compute-admin username $OS_USERNAME
        change_value $CONF compute-admin password $OS_PASSWORD
        change_value $CONF compute-admin tenant_name $OS_TENANT_NAME

        change_value $CONF identity-admin username $OS_USERNAME
        change_value $CONF identity-admin password $OS_PASSWORD
        change_value $CONF identity-admin tenant_name $OS_TENANT_NAME

        change_value $CONF network api_version $TOS__NETWORK__API_VERSION
    popd

    #export PYTHONPATH="$PWD/tempest:$PYTHONPATH"

    echo "================================================================================="
    echo "Running tempest..."
    nosetests -s -v --with-xunit --xunit-file=nosetests.xml $TESTCASE
    TEMPEST_RET=$?

    if [ "$TOS_DELETE_ENTITIES" = "true" ]; then
        echo "================================================================================="
        echo "Clean Tempest's environment..."
        glance image-delete $(get_id $TOS_IMAGE_NAME glance image-list)
        glance image-delete $(get_id $TOS_IMAGE_NAME_ALT glance image-list)
        nova flavor-delete $TOS_FLAVOR_REF
        nova flavor-delete $TOS_FLAVOR_REF_ALT
        keystone user-role-remove --user-id $(get_id $TOS_USERNAME keystone user-list) --role-id $(get_id $TOS_MEMBER_ROLE_NAME keystone role-list) --tenant-id $(get_id $TOS_TENANT_NAME keystone tenant-list)
        keystone user-role-remove --user-id $(get_id $TOS_USERNAME_ALT keystone user-list) --role-id $(get_id $TOS_MEMBER_ROLE_NAME keystone role-list) --tenant-id $(get_id $TOS_TENANT_NAME_ALT keystone tenant-list)
        keystone user-delete $(get_id $TOS_USERNAME keystone user-list)
        keystone user-delete $(get_id $TOS_USERNAME_ALT keystone user-list)
        net_delete $TOS_TENANT_NAME
        net_delete $TOS_TENANT_NAME_ALT
        keystone tenant-delete $(get_id $TOS_TENANT_NAME keystone tenant-list)
        keystone tenant-delete $(get_id $TOS_TENANT_NAME_ALT keystone tenant-list)
    fi

    XML_FILE=$TEMPEST_DIR/nosetests_table.xml
    cp $TEMPEST_DIR/nosetests.xml $XML_FILE
    XSL_FILE=xunit.xsl
    cp $TOP_DIR/$XSL_FILE $TEMPEST_DIR/
    if [ "$(grep -Eo "xml-stylesheet" $XML_FILE)" == "" ]; then
        sed -ie "0,/\?></ s/?></?><?xml-stylesheet type=\"text\/xsl\" href=\"$XSL_FILE\"?></" "$XML_FILE"
    fi

    deactivate

popd
exit $TEMPEST_RET

