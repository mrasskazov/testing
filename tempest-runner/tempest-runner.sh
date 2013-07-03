#!/bin/bash -x

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

export TESTCASE=${TESTCASE:-tempest/tests}
export COMPONENT=${COMPONENT:-all}
export TYPE=${TYPE:-all}

export OS_USERNAME=${OS_USERNAME:-admin}
export OS_PASSWORD=${OS_PASSWORD:-secrete}
export OS_TENANT_NAME=${OS_TENANT_NAME:-admin}
export OS_AUTH_STRATEGY=${OS_AUTH_STRATEGY:-keystone}

export REINSTALL_VIRTUALENV=${REINSTALL_VIRTUALENV:-false}
export CREATE_ENTITIES=${CREATE_ENTITIES:-true}
export DELETE_ENTITIES=${DELETE_ENTITIES:-false}

# detect/define some parameters
export CIRROS_HOST=http://download.cirros-cloud.net/
export CIRROS_RELEASE=$(wget -qO- $CIRROS_HOST/version/released)
export IMAGE_LINK=${IMAGE_LINK:-"$CIRROS_HOST/$CIRROS_RELEASE/cirros-$CIRROS_RELEASE-x86_64-disk.img"}
export IMAGE_NAME=${IMAGE_NAME:-tempest-cirros-01}
export IMAGE_LINK_ALT=${IMAGE_LINK_ALT:-$IMAGE_LINK}
export IMAGE_NAME_ALT=${IMAGE_NAME_ALT:-tempest-cirros-02}

export MEMBER_ROLE_NAME=${MEMBER_ROLE_NAME:-Member}
export DB_HA_HOST=${DB_HA_HOST:-localhost}


ini_param () {
    # TODO: error with not founded section/parameter needed.
    # or creating it if $5==CREATE
    FILENAME=$1
    SECTION=$2
    PARAM=$3
    VALUE=$4
    if [ "$SECTION" == "everywhere" ]; then
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
        echo "Wrong system variable value: \$MEMBER_ROLE_NAME=$MEMBER_ROLE_NAME"
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
        IMAGE_FILE_NAME=.$(echo $3 | grep -Eo '/[^/]*?$')
        glance --debug image-create --is-public $1 --name $2 --file $IMAGE_FILE_NAME --disk-format $4 --container-format $5 || exit 1
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


pushd $TOP_DIR/../..
    echo "================================================================================="
    route -n
    echo "================================================================================="
    find . -name *.pyc -delete
    if [ "$REINSTALL_VIRTUALENV" = "true" ]; then
        rm -rf venv_tempest
    fi
    virtualenv venv_tempest
    . venv_tempest/bin/activate
    pip install -r $TOP_DIR/tempest-runner-pre-requires || exit 1
    pip install -r $TEMPEST_DIR/tools/pip-requires || exit 1
    pip install -r $TEMPEST_DIR/tools/test-requires || exit 1
    pip install -r $TOP_DIR/tempest-runner-requires || exit 1


    pushd $TEMPEST_DIR
        ### DEFAULT CONFIG PARAMETERS ###
        export LAST_COMMITS=$(git log --pretty=oneline --max-count=100)
        if [ -n "$(echo $LAST_COMMITS | grep a6b85b82adbd371864cd1ee22f6d5b30338bb838)" ]; then
            source $TOP_DIR/rc.grizzly
        elif [ -n "$(echo $LAST_COMMITS | grep 444c3e64ed1347adcfc4204c1e585e2d91022722)" ]; then
            source $TOP_DIR/rc.folsom
        else
            echo "ERROR: Can not detect Tempest release"
            exit 1
        fi


        if [ "$CREATE_ENTITIES" = "true" ]; then
            echo "================================================================================="
            echo "Preparing Tempest's environment..."

            tenant_create $TOS__IDENTITY__TENANT_NAME
            user_create $TOS__IDENTITY__USERNAME $TOS__IDENTITY__TENANT_NAME $TOS__IDENTITY__PASSWORD $TOS__IDENTITY__USERNAME@$TOS__IDENTITY__TENANT_NAME.qa true
            user_role_add $TOS__IDENTITY__USERNAME $TOS__IDENTITY__TENANT_NAME $MEMBER_ROLE_NAME
            #net_create $TOS__IDENTITY__TENANT_NAME 10.0.1.0/24

            tenant_create $TOS__IDENTITY__ALT_TENANT_NAME
            user_create $TOS__IDENTITY__ALT_USERNAME $TOS__IDENTITY__ALT_TENANT_NAME $TOS__IDENTITY__ALT_PASSWORD $TOS__IDENTITY__ALT_USERNAME@$TOS__IDENTITY__ALT_TENANT_NAME.qa true
            user_role_add $TOS__IDENTITY__ALT_USERNAME $TOS__IDENTITY__ALT_TENANT_NAME $MEMBER_ROLE_NAME
            #net_create $TOS__IDENTITY__ALT_TENANT_NAME 10.0.2.0/24

            flavor_create true f64_1 $TOS__COMPUTE__FLAVOR_REF 64 0 1
            flavor_create true f64_2 $TOS__COMPUTE__FLAVOR_REF_ALT 64 0 1

            # is-public name disk-format IMAGE_LINK container-format
            image_create_img true $IMAGE_NAME $IMAGE_LINK qcow2 bare
            export TOS__COMPUTE__IMAGE_REF=${TOS__COMPUTE__IMAGE_REF:-$(get_id $IMAGE_NAME glance image-list)}
            image_create_img true $IMAGE_NAME_ALT $IMAGE_LINK_ALT qcow2 bare
            export TOS__COMPUTE__IMAGE_REF_ALT=${TOS__COMPUTE__IMAGE_REF_ALT:-$(get_id $IMAGE_NAME_ALT glance image-list)}

        fi

        echo "================================================================================="
        echo "Generating Tempest's config..."
        pushd etc
            ORIG=tempest.conf.sample
            CONF=tempest.conf
            cp -f $ORIG $CONF

            env | grep ^TOS_
            #env | awk -F '__' '/^TOS__/ {s=$2; gsub("_","-",s); v=split($3,kv,"="); end; print tolower(s" "kv[1])" "kv[2]}' | xargs --verbose -n3 -i% ini_param $CONF %
            for p in $(env | awk -F '__' '/^TOS__/ {s=$2; gsub("_","-",s); v=split($3,kv,"="); end; print tolower(s"="kv[1])"="kv[2]}')
            do
                sec=$(echo $p | cut -d "=" -f1)
                par=$(echo $p | cut -d "=" -f2)
                val=$(echo $p | cut -d "=" -f3)
                ini_param $CONF $sec $par $val
            done
        popd

        #export PYTHONPATH="$PWD/tempest:$PYTHONPATH"

        echo "================================================================================="
        echo "Running tempest..."

        if [[ "$COMPONENT" != "all" ]] && [[ "$TYPE" != "all" ]]; then
            nosetests -s -v --with-xunit --xunit-file=nosetests.xml --eval-attr "(component and '$COMPONENT' in component) and type == '$TYPE'" $TESTCASE
        elif [[ "$COMPONENT" != "all" ]]; then
            nosetests -s -v --with-xunit --xunit-file=nosetests.xml --eval-attr "(component and '$COMPONENT' in component)" $TESTCASE
        elif [[ "$TYPE" != "all" ]]; then
            nosetests -s -v --with-xunit --xunit-file=nosetests.xml --eval-attr "type == '$TYPE'" $TESTCASE
        else
            nosetests -s -v --with-xunit --xunit-file=nosetests.xml $TESTCASE
        fi

        #nosetests -s -v --with-xunit --xunit-file=nosetests.xml $TESTCASE
        TEMPEST_RET=$?

        if [ "$DELETE_ENTITIES" = "true" ]; then
            echo "================================================================================="
            echo "Clean Tempest's environment..."
            glance image-delete $(get_id $IMAGE_NAME glance image-list)
            glance image-delete $(get_id $IMAGE_NAME_ALT glance image-list)
            nova flavor-delete $TOS__COMPUTE__FLAVOR_REF
            nova flavor-delete $TOS__COMPUTE__FLAVOR_REF_ALT
            keystone user-role-remove --user-id $(get_id $TOS__IDENTITY__USERNAME keystone user-list) --role-id $(get_id $MEMBER_ROLE_NAME keystone role-list) --tenant-id $(get_id $TOS__IDENTITY__TENANT_NAME keystone tenant-list)
            keystone user-role-remove --user-id $(get_id $TOS__IDENTITY__ALT_USERNAME keystone user-list) --role-id $(get_id $MEMBER_ROLE_NAME keystone role-list) --tenant-id $(get_id $TOS__IDENTITY__ALT_TENANT_NAME keystone tenant-list)
            keystone user-delete $(get_id $TOS__IDENTITY__USERNAME keystone user-list)
            keystone user-delete $(get_id $TOS__IDENTITY__ALT_USERNAME keystone user-list)
            net_delete $TOS__IDENTITY__TENANT_NAME
            net_delete $TOS__IDENTITY__ALT_TENANT_NAME
            keystone tenant-delete $(get_id $TOS__IDENTITY__TENANT_NAME keystone tenant-list)
            keystone tenant-delete $(get_id $TOS__IDENTITY__ALT_TENANT_NAME keystone tenant-list)
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
popd
exit $TEMPEST_RET

