#!/bin/bash -x
TOP_DIR=$(cd $(dirname "$0") && pwd)

TEMPEST_DIR=$(readlink -f $TOP_DIR/../../tempest)

export OS_AUTH_URL=${OS_AUTH_URL:-auto}
export AUTH_PORT=${AUTH_PORT:-5000}
export AUTH_API_VERSION=${AUTH_API_VERSION:-v2.0}

export EXCLUDE_LIST=".*boto.*|.*nova_manage.*"

quit () {
    EXIT_CODE=${1:0}
    shift
    echo $@
    rm $LOCK_FILE
    exit $EXIT_CODE
}

map_os_release () {
    OS_VERSION=$(echo $CLUSTER_VERSION | grep -Eo '[0-9]+\.[0-9]+')
    case "$OS_VERSION" in
        "2013.1")
            OS_RELEASE=grizzly
            ;;
        "2013.2")
            OS_RELEASE=havana
            ;;
        *)
            quit 1 "ERROR: Can not map OpenStack release"
    esac
}

revert_env () {
    if [ -z "$SNAPSHOT" ]; then
        echo "Using current state of environment"
    else
        virsh list --all | grep 'running$' | awk '/'${ENV}'/ {print $2}' | xargs --verbose -n1 -i% virsh suspend %
        for D in $(virsh list --all |  awk '/'${ENV}'/ {print $2}'); do
            echo $D
            #S=$(virsh -q snapshot-list $D | grep -v 'shutoff$' | awk '/'$SNAPSHOT'/ {print $1}')
            S=$(virsh -q snapshot-list $D | awk '/ '$SNAPSHOT' / {print $1}')
            if [ -z "$S" ]; then
                virsh list --all | grep 'paused$' | awk '/'${ENV}'/ {print $2}' | xargs --verbose -n1 -i% virsh resume %
                quit 2 "Snapshot '$SNAPSHOT' is not found for domain '$D'"
            fi
            if [ -n "$S" ]; then
                echo revert to $S
                virsh snapshot-revert $D $S
            fi
        done
    fi
    virsh list --all | grep 'paused$' | awk '/'${ENV}'/ {print $2}' | xargs --verbose -n1 -i% virsh resume %
    sleep 10
}

if [ "$OS_AUTH_URL" = "auto" ]; then
    echo "================================================================================="

    unset OS_AUTH_URL
    if [ -z "$(virsh list --all | grep ${ENV}_admin)" ]; then
        quit 3 "Environment '$ENV' is not found"
    fi

    mkdir -p /tmp/tempest_runner
    LOCK_FILE=/tmp/tempest_runner/${ENV}.blocked
    if [[ -f "$LOCK_FILE" ]]; then
        echo "Environment '$ENV' already in use by:"
        cat $LOCK_FILE
        quit 4 "Environment '$ENV' already in use"
    else
        echo "Jenkins: ${JENKINS_URL}" > $LOCK_FILE
        echo "Job: ${JOB_NAME} (${JOB_URL})" >> $LOCK_FILE
        echo "Build: ${BUILD_NUMBER} (${BUILD_URL})" >> $LOCK_FILE
        echo "Started: ${BUILD_ID}" >> $LOCK_FILE
        echo "Lock file: ${LOCK_FILE}" >> $LOCK_FILE
    fi

    echo "================================================================================="
    revert_env


    ADMIN_IP=$(virsh net-dumpxml ${ENV}_admin | grep -P "(\d+\.){3}"  -o | awk '{print $0"2"}')
    API_URL="http://$ADMIN_IP:8000"
    NAILGUN="curl -s -H \"Accept: application/json\" -X GET ${API_URL}"

    # get cluster config via Nailgun API
    CLUSTER_ID=$(${NAILGUN}/api/clusters/ | \
        python -c 'import json,sys;obj=json.load(sys.stdin);print obj[0]["id"]') || quit 224 "Can not detect cluster paramaters"
    CLUSTER_MODE=$(${NAILGUN}/api/clusters/$CLUSTER_ID/ | \
        python -c 'import json,sys;obj=json.load(sys.stdin);print obj["mode"]') || quit 224 "Can not detect cluster paramaters"
    export CLUSTER_NET_PROVIDER=$(${NAILGUN}/api/clusters/$CLUSTER_ID/ | \
        python -c 'import json,sys;obj=json.load(sys.stdin);print obj["net_provider"]') || quit 224 "Can not detect cluster paramaters"
    CLUSTER_NET_SEGMENT_TYPE=$(${NAILGUN}/api/clusters/$CLUSTER_ID/ | \
        python -c 'import json,sys;obj=json.load(sys.stdin);print obj["net_segment_type"]') || quit 224 "Can not detect cluster paramaters"
    CLUSTER_RELEASE_ID=$(${NAILGUN}/api/clusters/$CLUSTER_ID/ | \
        python -c 'import json,sys;obj=json.load(sys.stdin);print obj["release"]["id"]') || quit 224 "Can not detect cluster paramaters"
    CLUSTER_OPERATING_SYSTEM=$(${NAILGUN}/api/releases/ | \
        python -c "import json,sys;obj=json.load(sys.stdin);print [_ for _ in obj if _['id'] == ${CLUSTER_RELEASE_ID}][0]['operating_system']") || quit 224 "Can not detect cluster paramaters"
    CLUSTER_VERSION=$(${NAILGUN}/api/releases/ | \
        python -c "import json,sys;obj=json.load(sys.stdin);print [_ for _ in obj if _['id'] == ${CLUSTER_RELEASE_ID}][0]['version']") || quit 224 "Can not detect cluster paramaters"
    map_os_release
    CLUSTER_VERSION_NAME=$(${NAILGUN}/api/releases/ | \
        python -c "import json,sys;obj=json.load(sys.stdin);print [_ for _ in obj if _['id'] == ${CLUSTER_RELEASE_ID}][0]['name']") || quit 224 "Can not detect cluster paramaters"

    # detect OS_AUTH_URL
    if [ "$CLUSTER_MODE" = "multinode" ]; then
        export AUTH_HOST=${AUTH_HOST:-$(${NAILGUN}/api/nodes | \
            python -c 'import json,sys;obj=json.load(sys.stdin);nd=[o for o in obj if "controller" in o["roles"]][0]["network_data"];print [n for n in nd if n["name"]=="public"][0]["ip"].split("/")[0]')} || quit 224 "Can not detect cluster paramaters"
        export DB_HOST=${DB_HOST:-$(${NAILGUN}/api/nodes | \
            python -c 'import json,sys;obj=json.load(sys.stdin);nd=[o for o in obj if "controller" in o["roles"]][0]["network_data"];print [n for n in nd if n["name"]=="management"][0]["ip"].split("/")[0]')} || quit 224 "Can not detect cluster paramaters"
    elif [ "$CLUSTER_MODE" = "ha_compact" ]; then
        export AUTH_HOST=${AUTH_HOST:-$(${NAILGUN}/api/clusters/$CLUSTER_ID/network_configuration/${CLUSTER_NET_PROVIDER} | \
            python -c 'import json,sys;obj=json.load(sys.stdin);print obj["public_vip"]')} || quit 224 "Can not detect cluster paramaters"
        export DB_HOST=${DB_HOST:-$(${NAILGUN}/api/clusters/$CLUSTER_ID/network_configuration/${CLUSTER_NET_PROVIDER} | \
            python -c 'import json,sys;obj=json.load(sys.stdin);print obj["management_vip"]')} || quit 224 "Can not detect cluster paramaters"
    fi

    #detect DB_URI
    #DB_URI=$(ssh root@$AUTH_HOST grep 'sql_connection' /etc/nova/nova.conf | awk -F '[ =]' '{print $NF}')
    #DB_URI=$(echo $DB_URI | sed -e "s/@.*\//@$DB_HOST\//")

    # detect OS_AUTH_URL
    export OS_AUTH_URL=${OS_AUTH_URL:-"http://$AUTH_HOST:$AUTH_PORT/$AUTH_API_VERSION/"}

    # detect credentials
    export OS_USERNAME=${OS_USERNAME:-$(${NAILGUN}/api/clusters/$CLUSTER_ID/attributes | \
        python -c 'import json,sys;obj=json.load(sys.stdin);print obj["editable"]["access"]["user"]["value"]')} || quit 224 "Can not detect cluster paramaters"
    export OS_PASSWORD=${OS_PASSWORD:-$(${NAILGUN}/api/clusters/$CLUSTER_ID/attributes | \
        python -c 'import json,sys;obj=json.load(sys.stdin);print obj["editable"]["access"]["password"]["value"]')} || quit 224 "Can not detect cluster paramaters"
    export OS_TENANT_NAME=${OS_TENANT_NAME:-$(${NAILGUN}/api/clusters/$CLUSTER_ID/attributes | \
        python -c 'import json,sys;obj=json.load(sys.stdin);print obj["editable"]["access"]["tenant"]["value"]')} || quit 224 "Can not detect cluster paramaters"

    echo ""
    ${NAILGUN}/api/clusters/$CLUSTER_ID/network_configuration/$CLUSTER_NET_PROVIDER
    echo "" 

fi


# check OS_AUTH_URL
export TEST_AUTH_URL="$(wget -qO- $OS_AUTH_URL | grep $AUTH_API_VERSION)"
if [ -z "$TEST_AUTH_URL" ]; then
    quit 5 "Could not connect to OS_AUTH_URL=$OS_AUTH_URL"
fi


export AUTH_HOST=${AUTH_HOST:-$(echo $OS_AUTH_URL | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}')}
export AUTH_PORT=${AUTH_PORT:-$(echo $OS_AUTH_URL | grep -Eo ':([0-9]{1,5})' | cut -d ":" -f2)}
export AUTH_API_VERSION=${AUTH_API_VERSION:-$(echo $OS_AUTH_URL | grep -Eo 'v([0-9\.])+')}

#export TESTCASE=${TESTCASE:-tempest/tests}
export COMPONENT=${COMPONENT:-all}
export COMPONENT=$(echo ${COMPONENT})
export TYPE=${TYPE:-smoke}
export TYPE=$(echo ${TYPE})

export OS_USERNAME=${OS_USERNAME:-admin}
export OS_PASSWORD=${OS_PASSWORD:-nova}
export OS_TENANT_NAME=${OS_TENANT_NAME:-admin}
export OS_AUTH_STRATEGY=${OS_AUTH_STRATEGY:-keystone}

export REINSTALL_VIRTUALENV=${REINSTALL_VIRTUALENV:-false}
export CREATE_ENTITIES=${CREATE_ENTITIES:-true}
export DELETE_ENTITIES=${DELETE_ENTITIES:-true}

# detect/define some parameters
export CIRROS_HOST=http://download.cirros-cloud.net/
export CIRROS_RELEASE=$(wget -qO- $CIRROS_HOST/version/released)
export IMAGE_LINK=${IMAGE_LINK:-"$CIRROS_HOST/$CIRROS_RELEASE/cirros-$CIRROS_RELEASE-x86_64-disk.img"}
export IMAGE_NAME=${IMAGE_NAME:-tempest-cirros-01}
export IMAGE_LINK_ALT=${IMAGE_LINK_ALT:-$IMAGE_LINK}
export IMAGE_NAME_ALT=${IMAGE_NAME_ALT:-tempest-cirros-02}

export MEMBER_ROLE_NAME=${MEMBER_ROLE_NAME:-Member}
export DB_HA_HOST=${DB_HA_HOST:-$AUTH_HOST}


if [ "$CLUSTER_NET_PROVIDER" == "neutron" ]; then
    export PUBLIC_NETWORK_NAME=${PUBLIC_NETWORK_NAME:-net04_ext}
    export INTERNAL_NETWORK_NAME=${INTERNAL_NETWORK_NAME:-net04}
    export PUBLIC_ROUTER_NAME=${PUBLIC_ROUTER_NAME:-router04}
else
    export PUBLIC_NETWORK_NAME=${PUBLIC_NETWORK_NAME:-novanetwork}
fi

ini_param () {
    # TODO: error with not founded section/parameter needed.
    # or creating it if $5==CREATE
    FILENAME=$1
    SECTION=$2
    PARAM=$3
    VALUE=$4
    if [ "$SECTION" == "everywhere" ]; then
        # change all the matching
        sed -i -e "s|\(^$PARAM\).*=.*|\1 = $VALUE|" $FILENAME
    else
        # change only in "$SECTION"
        sed -ine "/^\[$SECTION\].*/,/^$PARAM.*=.*/ s|\(^$PARAM\).*=.*|\1 = $VALUE|" $FILENAME
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
    echo "---------------------------------------------------------------------------------"
    # tenant_name
    if [ "$(get_id $1 keystone tenant-list)" == "" ]; then
        keystone --debug tenant-create --name $1 || quit 6 "Can not create tenant"
        echo $?
    fi
}

user_create () {
    echo "---------------------------------------------------------------------------------"
    # user_name tenant_name password email enabled
    if [ "$(get_id $1 keystone user-list)" == "" ]; then
        keystone --debug user-create --name $1 --tenant-id $(get_id $2 keystone tenant-list) --pass $3 --email $4 --enabled $5 || quit 7 "Can not create user"
        echo $?
    fi
}

user_role_add () {
    echo "---------------------------------------------------------------------------------"
    # user_name tenant_name role_name
    if [ "$(get_id $3 keystone role-list)" != "" ]; then
        if [ "$(keystone user-role-list --user-id $(get_id $1 keystone user-list) --tenant-id $(get_id $2 keystone tenant-list) | grep '^| [a-z0-9]' | grep -vi ' id ')" == "" ]; then
            keystone --debug user-role-add --user-id $(get_id $1 keystone user-list) --tenant-id $(get_id $2 keystone tenant-list) --role-id $(get_id $3 keystone role-list) || quit 8 "Can not create role"
            echo $?
        fi
    else
        echo "Wrong system variable value: \$MEMBER_ROLE_NAME=$MEMBER_ROLE_NAME"
    fi
}

flavor_create () {
    echo "---------------------------------------------------------------------------------"
    # is_public flavor_name id ram disk vcpus
    if [ "$(get_id $2 nova flavor-list)" == "" ]; then
        nova --debug flavor-create --is-public $1 $2 $3 $4 $5 $6
        echo $?
    fi
}

image_create_img () {
    echo "---------------------------------------------------------------------------------"
    # is-public name IMANE_LINK disk-format container-format
    if [ "$(get_id $2 glance image-list)" == "" ]; then
        wget --progress=dot:mega -c $3
        IMAGE_FILE_NAME=.$(echo $3 | grep -Eo '/[^/]*?$')
        glance --debug image-create --is-public $1 --name $2 --file $IMAGE_FILE_NAME --disk-format $4 --container-format $5 || quit 9 "Can not upload image"
        echo $?
    fi
}

net_create () {
    echo "---------------------------------------------------------------------------------"
    # tenant_name sip_lease gateway eg_id net_type ip_version router_name net_name subnet_name
    # if [ "$(get_id $2 glance image-list)" == "" ]; then
    if [ "$1" == "shared" ]; then
        local SHARED="--shared"
        shift
    fi
    TENANT_ID=$(get_id $1 keystone tenant-list)
    IP_LEASE=${2:-10.0.1.0/24}
    DEF_GATEWAY=$(echo $(echo $IP_LEASE | grep -Eo '([0-9]{1,3}\.){3}')1)
    GATEWAY=${3:-$DEF_GATEWAY}
    MAX_SEG_ID=$(for n in $(neutron net-list | grep '^| [a-z0-9]' | grep -v ' id ' | awk '{print $2}'); do neutron net-show $n | awk '/segmentation_id/ {print $4}'; done | sort -g | tail -n1)
    SEG_ID=${4:-$(($MAX_SEG_ID + 1))}
    CUR_NET_TYPE=$(neutron net-show $INTERNAL_NETWORK_NAME | awk '/network_type/ {print $4}')
    NET_TYPE=${5:-$CUR_NET_TYPE}
    CUR_IP_VERSION=$(neutron subnet-show ${INTERNAL_NETWORK_NAME}__subnet | awk '/ip_version/ {print $4}')
    IP_VERSION=${6:-$CUR_IP_VERSION}
    ROUTER_NAME=${7:-$PUBLIC_ROUTER_NAME}
    NET_NAME=${8:-${1}_net}
    SUBNET_NAME=${9:-${1}_subnet}

    CUR_PHYS_NET=$(neutron net-show $INTERNAL_NETWORK_NAME | awk '/physical_network/ {print $4}')
    if [ "$NET_TYPE" != "gre" ]; then
        PHYS_NET_OPT="--provider:physical_network ${CUR_PHYS_NET}"
    fi

    if [ "$NET_TYPE" != "flat" ]; then
        SEG_ID_OPT="--provider:segmentation_id $SEG_ID"
    fi

    if [ "$(get_id $NET_NAME neutron net-list)" == "" ]; then
        neutron --verbose net-create --tenant_id $TENANT_ID $NET_NAME $SHARED $PHYS_NET_OPT --provider:network_type $NET_TYPE $SEG_ID_OPT || quit 10 "Can not create network"
    fi
    NET_ID=$(get_id $NET_NAME neutron net-list)

    if [ "$(get_id $SUBNET_NAME neutron subnet-list)" == "" ]; then
        neutron --verbose subnet-create --name $SUBNET_NAME --tenant_id $TENANT_ID --ip_version $IP_VERSION $NET_ID --gateway $GATEWAY $IP_LEASE || quit 11 "Can not create subnet"
    fi
    SUBNET_ID=$(get_id $SUBNET_NAME neutron subnet-list)

    #if [ "$(get_id $ROUTER_NAME neutron router-list)" == "" ]; then
        #neutron router-create --tenant_id $TENANT_ID $ROUTER_NAME || quit 12 "can not create router"
    #fi
    ROUTER_ID=$(get_id $ROUTER_NAME neutron router-list)

    neutron --verbose router-interface-add ${ROUTER_ID} ${SUBNET_ID}

    # for external network
    #neutron router-gateway-set --request-format json $ROUTER_ID $NET_ID
}

net_delete () {
    echo "---------------------------------------------------------------------------------"
    # tenant_name router_name net_name subnet_name
    # if [ "$(get_id $2 glance image-list)" == "" ]; then
    TENANT_ID=$(get_id $1 keystone tenant-list)
    ROUTER_NAME=${2:-$PUBLIC_ROUTER_NAME}
    NET_NAME=${3:-${1}_net}
    SUBNET_NAME=${4:-${1}_subnet}

    ### EMERGENCY CLEANING ###
    # for r in $(neutron router-list | awk '/t[12]_router/ {print $2}'); do for sn in $(neutron subnet-list | awk '/_net/ {print $2}'); do neutron router-interface-delete $r $sn; done; done
    # neutron subnet-list | awk '/_net/ {print $2}' | xargs -n1 -i% neutron subnet-delete %
    # neutron net-list | awk '/_net/ {print $2}' | xargs -n1 -i% neutron net-delete %
    # neutron router-list | awk '/t[12]_router/ {print $2}' | xargs -n1 -i% neutron router-delete %

    neutron --verbose router-interface-delete $(get_id $ROUTER_NAME neutron router-list) $(get_id $SUBNET_NAME neutron subnet-list)
    neutron --verbose subnet-delete $(get_id $SUBNET_NAME neutron subnet-list)
    neutron --verbose net-delete $(get_id $NET_NAME neutron net-list)
    #neutron router-delete $(get_id $ROUTER_NAME neutron router-list)
}

detect_tempest_release () {
    echo "---------------------------------------------------------------------------------"
    if [ -z "$TEMPEST_RELEASE" ]; then
        DIR=${1:-TEMPEST_DIR}
        pushd ${DIR}
            export LAST_COMMITS=$(git log --decorate --oneline --max-count=100)
            if [ -n "$(echo $LAST_COMMITS | grep havana)" ]; then
                TEMPEST_RELEASE=havana
            elif [ -n "$(echo $LAST_COMMITS | grep grizzly)" ]; then
                TEMPEST_RELEASE=grizzly
            elif [ -n "$(echo $LAST_COMMITS | grep folsom)" ]; then
                TEMPEST_RELEASE=folsom
            else
                quit 14 "ERROR: Can not detect Tempest release"
            fi
        popd
    fi
}

fetch_tempest_repo () {
    echo "---------------------------------------------------------------------------------"
    pushd $TOP_DIR/../..
        TEMPEST_REPO=${TEMPEST_REPO:-https://github.com/Mirantis/tempest.git}
        TEMPEST_REFSPEC=${TEMPEST_REFSPEC:-$TEMPEST_RELEASE}
        if [[ ! -r $TEMPEST_DIR ]]; then
            git clone $TEMPEST_REPO
        fi
        pushd $TEMPEST_DIR
            git fetch $TEMPEST_REPO $TEMPEST_REFSPEC && git checkout FETCH_HEAD
        popd
    popd
}

pip_fail () {
    rm ${DIR}.reinstalling
    quit $@
}

install_virtualenv () {
    echo "---------------------------------------------------------------------------------"
    DIR=venv_tempest_${OS_RELEASE}
    pushd $HOME
        touch ${DIR}.reinstalling
        source $DIR/bin/activate
        pip install -r $TOP_DIR/tempest-runner-pre-requires || pip_fail 212 "Can not install virtual environment"
        case "$OS_RELEASE" in
            "grizzly")
                pip install -r $TEMPEST_DIR/tools/pip-requires || pip_fail 212 "Can not install virtual environment"
                pip install -r $TEMPEST_DIR/tools/test-requires || pip_fail 212 "Can not install virtual environment"
                ;;
            "havana")
                pip install -r $TEMPEST_DIR/requirements.txt || pip_fail 212 "Can not install virtual environment"
                pip install -r $TEMPEST_DIR/test-requirements.txt || pip_fail 212 "Can not install virtual environment"
                ;;
            *)
                echo "ERROR: Can not install virtual environment for '$OS_RELEASE' OpenStack release"
                rm ${DIR}.reinstalling
                exit 1
        esac
        pip install -r $TOP_DIR/tempest-runner-requires || pip_fail 212 "Can not install virtual environment"
        deactivate
        mv ${DIR}.reinstalling ${DIR}.done
    popd
}

use_virtualenv () {
    echo "---------------------------------------------------------------------------------"
    # start | stop
    DIR=venv_tempest_${OS_RELEASE}
    ACTION=${1:-start}
    if [ "$ACTION" = "start" ]; then
        pushd $HOME
            mkdir -p /tmp/${DIR}
            touch /tmp/${DIR}/${DIR}.busy$(ls /tmp/${DIR}/ | wc -l)

            WAIT_VENV=${WAIT_VENV:-600}
            while [[ -f "${DIR}.reinstalling" ]]; do
                if [[ ! -r $DIR ]]; then
                    rm ${DIR}.reinstalling
                fi
                WAIT_VENV=$(( $WAIT_VENV - 10 ))
                if [ "$WAIT_VENV" -lt 0 ]; then
                    rm /tmp/${DIR}/$(ls /tmp/${DIR}/ | tail -n 1)
                    quit 20 "Timeout waiting for virtual environment reinstalled. Can not use"
                fi
                sleep 10
            done

            if [[ (-r $DIR) && ("$REINSTALL_VIRTUALENV" == true) ]]; then
                WAIT_VENV=${WAIT_VENV:-8000}
                while [ "$(ls /tmp/${DIR}/ | wc -l)" -gt 1 ]; do
                    WAIT_VENV=$(( $WAIT_VENV - 10 ))
                    if [ "$WAIT_VENV" -lt 0 ]; then
                        rm /tmp/${DIR}/$(ls /tmp/${DIR}/ | tail -n 1)
                        quit 21 "Timeout waiting for virtual environment freed. Can not reinstall"
                    fi
                    sleep 10
                done
                rm -rf $DIR
            fi

            if [[ ! -r $DIR ]]; then
                touch ${DIR}.reinstalling
                rm ${DIR}.done
                virtualenv $DIR
                REINSTALL_VIRTUALENV=true
            fi

            if [[ ! -e ${DIR}.done ]]; then
                touch ${DIR}.reinstalling
                install_virtualenv
            fi

            source $DIR/bin/activate

        popd

    else
        deactivate
        rm /tmp/${DIR}/$(ls /tmp/${DIR}/ | tail -n 1)
    fi
}

detect_excludes () {
    VOLUME_ENABLED=$(keystone service-list | tail -n +4 | head -n -1 | awk '/volume/ {print $4}') # cinder
    [ -z "$VOLUME_ENABLED" ] && export EXCLUDE_LIST="$EXCLUDE_LIST|.*volume.*|.*cinder.*"
    #IMAGE_ENABLED=$(keystone service-list | tail -n +4 | head -n -1 | awk '/image/ {print $4}') # glance
    #ORCHESTRATION_ENABLED=$(keystone service-list | tail -n +4 | head -n -1 | awk '/orchestration/ {print $4}') # heat
    #IDENTITY_ENABLED=$(keystone service-list | tail -n +4 | head -n -1 | awk '/identity/ {print $4}') # keystone
    #COMPUTE_ENABLED=$(keystone service-list | tail -n +4 | head -n -1 | awk '/compute/ {print $4}') # nova
    #EC2_ENABLED=$(keystone service-list | tail -n +4 | head -n -1 | awk '/ec2/ {print $4}') # nova_ec2
    NETWORK_ENABLED=$(keystone service-list | tail -n +4 | head -n -1 | awk '/network/ {print $4}') # quantum
    [ -z "$NETWORK_ENABLED" ] && export EXCLUDE_LIST="$EXCLUDE_LIST|.*quantum.*|.*neutron.*"
    OBJECT_STORE_ENABLED=$(keystone service-list | tail -n +4 | head -n -1 | awk '/object-store/ {print $4}') # swift
    [ -z "$OBJECT_STORE_ENABLED" ] && export EXCLUDE_LIST="$EXCLUDE_LIST|.*object_storage.*"
    #S3_ENABLED=$(keystone service-list | tail -n +4 | head -n -1 | awk '/s3/ {print $4}') # swift_s3

    MURANO_ENABLED=$(${NAILGUN}/api/clusters/$CLUSTER_ID/attributes | \
        python -c 'import json,sys;obj=json.load(sys.stdin);print obj["editable"]["additional_components"]["murano"]["value"]')
    [ "$MURANO_ENABLED" != "True" ] && export EXCLUDE_LIST="$EXCLUDE_LIST|.*murano.*"
    SAVANNA_ENABLED=$(${NAILGUN}/api/clusters/$CLUSTER_ID/attributes | \
        python -c 'import json,sys;obj=json.load(sys.stdin);print obj["editable"]["additional_components"]["savanna"]["value"]')
    [ "$SAVANNA_ENABLED" != "True" ] && export EXCLUDE_LIST="$EXCLUDE_LIST|.*savanna.*"
    HEAT_ENABLED=$(${NAILGUN}/api/clusters/$CLUSTER_ID/attributes | \
        python -c 'import json,sys;obj=json.load(sys.stdin);print obj["editable"]["additional_components"]["heat"]["value"]')
    [ "$HEAT_ENABLED" != "True" ] && export EXCLUDE_LIST="$EXCLUDE_LIST|.*heat.*"
}

pushd $TOP_DIR/../..
    echo "================================================================================="
    find . -name *.pyc -delete

    TEMPEST_RELEASE=${TEMPEST_REFSPEC:-fuel/stable/$OS_RELEASE}
    [ -z "$OS_RELEASE" ] && quit 30 "OS_RELEASE not specified"

    if [ -z "$TESTCASE" ]; then
        if [ "$OS_RELEASE" = "grizzly" ]; then
            TESTCASE="tempest/tests"
        else
            TESTCASE="."
        fi
    fi


    fetch_tempest_repo
    use_virtualenv start
    detect_excludes


    ### DEFAULT CONFIG PARAMETERS ###
    #detect_tempest_release
    source $TOP_DIR/rc.${OS_RELEASE}

    for CLIENT in nova cinder glance keystone; do
        sudo ln -s $(which $CLIENT) /usr/local/bin/
    done

    pushd $TEMPEST_DIR


        if [ "$CREATE_ENTITIES" = "true" ]; then
            echo "================================================================================="
            echo "Preparing Tempest's environment..."

            [ "$CLUSTER_NET_PROVIDER" == "neutron" ]  && net_create shared $TOS__IDENTITY__ADMIN_TENANT_NAME 10.0.131.0/24

            tenant_create $TOS__IDENTITY__TENANT_NAME
            user_create $TOS__IDENTITY__USERNAME $TOS__IDENTITY__TENANT_NAME $TOS__IDENTITY__PASSWORD $TOS__IDENTITY__USERNAME@$TOS__IDENTITY__TENANT_NAME.qa true
            user_role_add $TOS__IDENTITY__USERNAME $TOS__IDENTITY__TENANT_NAME $MEMBER_ROLE_NAME
            [ "$CLUSTER_NET_PROVIDER" == "neutron" ]  && net_create $TOS__IDENTITY__TENANT_NAME 10.0.132.0/24

            tenant_create $TOS__IDENTITY__ALT_TENANT_NAME
            user_create $TOS__IDENTITY__ALT_USERNAME $TOS__IDENTITY__ALT_TENANT_NAME $TOS__IDENTITY__ALT_PASSWORD $TOS__IDENTITY__ALT_USERNAME@$TOS__IDENTITY__ALT_TENANT_NAME.qa true
            user_role_add $TOS__IDENTITY__ALT_USERNAME $TOS__IDENTITY__ALT_TENANT_NAME $MEMBER_ROLE_NAME
            [ "$CLUSTER_NET_PROVIDER" == "neutron" ]  && net_create $TOS__IDENTITY__ALT_TENANT_NAME 10.0.133.0/24

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
            nosetests -s -v -e "$EXCLUDE_LIST" --with-xunit --xunit-file=nosetests.xml --eval-attr "(component and '$COMPONENT' in component) and type == '$TYPE'" $TESTCASE
        elif [[ "$COMPONENT" != "all" ]]; then
            nosetests -s -v -e  "$EXCLUDE_LIST" --with-xunit --xunit-file=nosetests.xml --eval-attr "(component and '$COMPONENT' in component)" $TESTCASE
        elif [[ "$TYPE" != "all" ]]; then
            nosetests -s -v -e "$EXCLUDE_LIST" --with-xunit --xunit-file=nosetests.xml --eval-attr "type == '$TYPE'" $TESTCASE
        else
            nosetests -s -v -e "$EXCLUDE_LIST" --with-xunit --xunit-file=nosetests.xml $TESTCASE
        fi

        #nosetests -s -v -e "$EXCLUDE_LIST" --with-xunit --xunit-file=nosetests.xml $TESTCASE
        TEMPEST_RET=$?

        echo "================================================================================="
        if [ "$DELETE_ENTITIES" = "true" ]; then
            if [ "$TEMPEST_RET" = "0" ]; then
                echo "Clean Tempest's environment..."
                glance image-delete $(get_id $IMAGE_NAME glance image-list)
                glance image-delete $(get_id $IMAGE_NAME_ALT glance image-list)
                nova flavor-delete $TOS__COMPUTE__FLAVOR_REF
                nova flavor-delete $TOS__COMPUTE__FLAVOR_REF_ALT
                keystone user-role-remove --user-id $(get_id $TOS__IDENTITY__USERNAME keystone user-list) --role-id $(get_id $MEMBER_ROLE_NAME keystone role-list) --tenant-id $(get_id $TOS__IDENTITY__TENANT_NAME keystone tenant-list)
                keystone user-role-remove --user-id $(get_id $TOS__IDENTITY__ALT_USERNAME keystone user-list) --role-id $(get_id $MEMBER_ROLE_NAME keystone role-list) --tenant-id $(get_id $TOS__IDENTITY__ALT_TENANT_NAME keystone tenant-list)
                keystone user-delete $(get_id $TOS__IDENTITY__USERNAME keystone user-list)
                keystone user-delete $(get_id $TOS__IDENTITY__ALT_USERNAME keystone user-list)
                if [ "$CLUSTER_NET_PROVIDER" == "neutron" ]; then
                    net_delete $TOS__IDENTITY__TENANT_NAME
                    net_delete $TOS__IDENTITY__ALT_TENANT_NAME
                    net_delete $TOS__IDENTITY__ADMIN_TENANT_NAME
                fi
                keystone tenant-delete $(get_id $TOS__IDENTITY__TENANT_NAME keystone tenant-list)
                keystone tenant-delete $(get_id $TOS__IDENTITY__ALT_TENANT_NAME keystone tenant-list)
            else
                echo "Created entities is not deleted because of FAIL"
            fi
        fi

        XML_FILE=$TEMPEST_DIR/nosetests_table.xml
        cp $TEMPEST_DIR/nosetests.xml $XML_FILE
        XSL_FILE=xunit.xsl
        cp $TOP_DIR/$XSL_FILE $TEMPEST_DIR/
        if [ "$(grep -Eo "xml-stylesheet" $XML_FILE)" == "" ]; then
            sed -ie "0,/\?></ s/?></?><?xml-stylesheet type=\"text\/xsl\" href=\"$XSL_FILE\"?></" "$XML_FILE"
        fi

        use_virtualenv stop
    popd
popd
quit $TEMPEST_RET

