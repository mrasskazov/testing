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
TOS_IMAGE_LINK=${TOS_IMAGE_LINK:-'http://launchpad.net/cirros/trunk/0.3.0/+download/cirros-0.3.0-x86_64-disk.img'}
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
TOS_NETWORK_FOR_SSH=${TOS_NETWORK_FOR_SSH:-private}
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

tenant_id () {
    echo $(keystone tenant-list | grep " $1 " | cut -d ' ' -f2)
}
user_id () {
    echo $(keystone user-list | grep " $1 " | cut -d ' ' -f2)
}
role_id () {
    echo $(keystone role-list | grep " $1 " | cut -d ' ' -f2)
}
flavor_id () {
    echo $(nova flavor-list | grep " $1 " | cut -d ' ' -f2)
}
image_id () {
    echo $(glance image-list | grep " $1 " | cut -d ' ' -f2)
}

tenant_create () {
    # tenant_name
    if [ "$(tenant_id $1)" == "" ]; then
        keystone --debug tenant-create --name $1
        echo $?
    fi
}
user_create () {
    # user_name tenant_name password email enabled
    if [ "$(user_id $1)" == "" ]; then
        keystone --debug user-create --name $1 --tenant-id $(tenant_id $2) --pass $3 --email $4 --enabled $5
        echo $?
    fi
}
user_role_add () {
    # user_name tenant_name role_name
    if [ "$(role_id $3)" != "" ]; then
        if [ "$(keystone user-role-list --user-id $(user_id $1) --tenant-id $(tenant_id $2))" == "" ]; then
            keystone --debug user-role-add --user-id $(user_id $1) --tenant-id $(tenant_id $2) --role-id $(role_id $3)
            echo $?
        else
            echo "Role $3 in tenant $2 already assigned for user $1."
        fi
    else
        echo "Wrong system variable value: \$TOS_MEMBER_ROLE_NAME=$TOS_MEMBER_ROLE_NAME"
    fi
}
flavor_create () {
    # is_public flavor_name id ram disk vcpus
    if [ "$(flavor_id $2)" == "" ]; then
        nova --debug flavor-create --is-public $1 $2 $3 $4 $5 $6
        echo $?
    fi
}
image_create_img () {
    # is-public name IMANE_LINK disk-format container-format 
    if [ "$(image_id $2)" == "" ]; then
        wget --progress=dot:mega -c $3
        TOS_IMAGE_FILE_NAME=.$(echo $3 | grep -Eo '/[^/]*?$')
        glance --debug image-create --is-public $1 --name $2 --file $TOS_IMAGE_FILE_NAME --disk-format $4 --container-format $5
        echo $?
    fi
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
    pip install -r tools/pip-requires
    pip install -r tools/test-requires
    pip install -r $TOP_DIR/tempest-runner-pre-requires
    pip install -r $TOP_DIR/tempest-runner-requires

    if [ "$TOS_CREATE_ENTITIES" = "true" ]; then
        echo "================================================================================="
        echo "Preparing Tempest's environment..."

        tenant_create $TOS_TENANT_NAME
        user_create $TOS_USERNAME $TOS_TENANT_NAME $TOS_PASSWORD $TOS_USERNAME@$TOS_TENANT_NAME.qa true
        user_role_add $TOS_USERNAME $TOS_TENANT_NAME $TOS_MEMBER_ROLE_NAME

        tenant_create $TOS_TENANT_NAME_ALT
        user_create $TOS_USERNAME_ALT $TOS_TENANT_NAME_ALT $TOS_PASSWORD_ALT $TOS_USERNAME_ALT@$TOS_TENANT_NAME_ALT.qa true
        user_role_add $TOS_USERNAME_ALT $TOS_TENANT_NAME_ALT $TOS_MEMBER_ROLE_NAME

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

        change_value $CONF __ANY__ image_ref $(image_id $TOS_IMAGE_NAME)
        change_value $CONF __ANY__ image_ref_alt $(image_id $TOS_IMAGE_NAME_ALT)
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
        glance image-delete $(image_id $TOS_IMAGE_NAME)
        glance image-delete $(image_id $TOS_IMAGE_NAME_ALT)
        nova flavor-delete $TOS_FLAVOR_REF
        nova flavor-delete $TOS_FLAVOR_REF_ALT
        keystone user-role-remove --user-id $(user_id $TOS_USERNAME) --role-id $(role_id $TOS_MEMBER_ROLE_NAME) --tenant-id $(tenant_id $TOS_TENANT_NAME)
        keystone user-role-remove --user-id $(user_id $TOS_USERNAME_ALT) --role-id $(role_id $TOS_MEMBER_ROLE_NAME) --tenant-id $(tenant_id $TOS_TENANT_NAME_ALT)
        keystone user-delete $(user_id $TOS_USERNAME)
        keystone user-delete $(user_id $TOS_USERNAME_ALT)
        keystone tenant-delete $(tenant_id $TOS_TENANT_NAME)
        keystone tenant-delete $(tenant_id $TOS_TENANT_NAME_ALT)
    fi

    deactivate

popd
exit $TEMPEST_RET

