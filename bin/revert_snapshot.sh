#!/bin/bash

#DEBUG=echo

if [ -n "$1" ]; then
    #export ENV=3.2_fuelmain.system_test.centos.thread_3_system_test
    export ENV=$1
    echo "Environment: $ENV"
    dos.py show ${ENV} | python -c 'import sys,pprint; e=sys.stdin.readline(); exec "e="+e ; pprint.pprint(e)'
    if [ -n "$2" ]; then
        #export SNAPSHOT=deploy_neutron_vlan
        export SNAPSHOT=$2
        echo "Snapshot: $SNAPSHOT"
        echo "Reverting..."
        $DEBUG dos.py revert $ENV --snapshot-name $SNAPSHOT && dos.py resume $ENV && sleep 5


    else
        virsh snapshot-list ${ENV}_admin
        echo "============================================================"
        echo "Usage: $0 <env> <snapshot>"
    fi

    ADMIN_IP=$(virsh net-dumpxml ${ENV}_admin | grep -P "(\d+\.){3}"  -o | awk '{print $0"2"}')
    API_URL="http://$ADMIN_IP:8000"
    NAILGUN="curl -s -H \"Accept: application/json\" -X GET ${API_URL}"

    # get cluster config via Nailgun API
    CLUSTER_ID=$(${NAILGUN}/api/clusters/ | \
        python -c 'import json,sys;obj=json.load(sys.stdin);print obj[0]["id"]') || exit 224
    CLUSTER_MODE=$(${NAILGUN}/api/clusters/$CLUSTER_ID/ | \
        python -c 'import json,sys;obj=json.load(sys.stdin);print obj["mode"]') || exit 224
    CLUSTER_NET_PROVIDER=$(${NAILGUN}/api/clusters/$CLUSTER_ID/ | \
        python -c 'import json,sys;obj=json.load(sys.stdin);print obj["net_provider"]') || exit 224
    CLUSTER_NET_SEGMENT_TYPE=$(${NAILGUN}/api/clusters/$CLUSTER_ID/ | \
        python -c 'import json,sys;obj=json.load(sys.stdin);print obj["net_segment_type"]') || exit 224

    CLUSTER_RELEASE_ID=$(${NAILGUN}/api/clusters/$CLUSTER_ID/ | \
        python -c 'import json,sys;obj=json.load(sys.stdin);print obj["release"]["id"]') || exit 224
    CLUSTER_OPERATING_SYSTEM=$(${NAILGUN}/api/releases/ | \
        python -c "import json,sys;obj=json.load(sys.stdin);print [_ for _ in obj if _['id'] == ${CLUSTER_RELEASE_ID}][0]['operating_system']") || exit 224
    CLUSTER_VERSION=$(${NAILGUN}/api/releases/ | \
        python -c "import json,sys;obj=json.load(sys.stdin);print [_ for _ in obj if _['id'] == ${CLUSTER_RELEASE_ID}][0]['version']") || exit 224

# sync time on nodes by force
if [ -n "$2" ]; then
[ "$CLUSTER_OPERATING_SYSTEM" = "Ubuntu" ] && NTPD_SERVICE=ntp || NTPD_SERVICE=ntpd
expect << ENDOFEXPECT
spawn ssh root@$ADMIN_IP
expect "password: "
send "r00tme\r"
expect "# "
send "service ntpd stop; ntpdate pool.ntp.org; service ntpd start\r"
expect "# "
# work on admin node
#for N in $(ls /var/log/remote/ | grep node-); do echo 'ssh root@'$N' \"service ntpd stop; ntpdate pool.ntp.org; service ntpd start\"'; done | xargs --verbose -P0 -n1 -i% bash -c %
send "for N in \$\(ls /var/log/remote/ | grep node-\); do ssh root@\$\N \"service $NTPD_SERVICE stop; ntpdate pool.ntp.org; service $NTPD_SERVICE start\"; done\r"
expect "# "
send "exit\r"
expect eof
ENDOFEXPECT
fi

    # detect OS_AUTH_URL
    if [ "$CLUSTER_MODE" = "multinode" ]; then
        export AUTH_HOST=${AUTH_HOST:-$(${NAILGUN}"/api/nodes/?cluster_id=$CLUSTER_ID" | \
            python -c 'import json,sys;obj=json.load(sys.stdin);nd=[o for o in obj if "controller" in o["roles"]][0]["network_data"];print [n for n in nd if n["name"]=="public"][0]["ip"].split("/")[0]')} || exit 224
    elif [ "$CLUSTER_MODE" = "ha_compact" ]; then
        export AUTH_HOST=${AUTH_HOST:-$(${NAILGUN}/api/clusters/$CLUSTER_ID/network_configuration/${CLUSTER_NET_PROVIDER} | \
            python -c 'import json,sys;obj=json.load(sys.stdin);print obj["public_vip"]')} || exit 224
    fi

    export OS_AUTH_URL=${OS_AUTH_URL:-"http://$AUTH_HOST:5000/v2.0/"}

    # detect credentials
    OS_USERNAME=${OS_USERNAME:-$(${NAILGUN}/api/clusters/$CLUSTER_ID/attributes | \
        python -c 'import json,sys;obj=json.load(sys.stdin);print obj["editable"]["access"]["user"]["value"]')} || exit 224
    OS_PASSWORD=${OS_PASSWORD:-$(${NAILGUN}/api/clusters/$CLUSTER_ID/attributes | \
        python -c 'import json,sys;obj=json.load(sys.stdin);print obj["editable"]["access"]["password"]["value"]')} || exit 224
    OS_TENANT_NAME=${OS_TENANT_NAME:-$(${NAILGUN}/api/clusters/$CLUSTER_ID/attributes | \
        python -c 'import json,sys;obj=json.load(sys.stdin);print obj["editable"]["access"]["tenant"]["value"]')} || exit 224

    echo "Nodes:"
    ${NAILGUN}"/api/nodes/?cluster_id=$CLUSTER_ID" | \
        python -c 'import json,sys,pprint;obj=json.load(sys.stdin);nd=[{"fqdn":o["fqdn"],"roles":o["roles"],"ip":o["ip"],"os_platform":o["os_platform"]} for o in obj]; pprint.pprint(nd)'

    echo "ADMIN_IP=$ADMIN_IP"
    echo "API_URL=$API_URL"
    echo "CLUSTER_ID = $CLUSTER_ID"
    echo "CLUSTER_MODE=$CLUSTER_MODE"
    echo "CLUSTER_NET_PROVIDER=$CLUSTER_NET_PROVIDER"
    echo "CLUSTER_NET_SEGMENT_TYPE=$CLUSTER_NET_SEGMENT_TYPE"
    echo "CLUSTER_OPERATING_SYSTEM=$CLUSTER_OPERATING_SYSTEM"
    echo "CLUSTER_VERSION=$CLUSTER_VERSION"
    echo "OS_AUTH_URL=$OS_AUTH_URL"
    echo "OS_USERNAME=$OS_USERNAME"
    echo "OS_PASSWORD=$OS_PASSWORD"
    echo "OS_TENANT_NAME=$OS_TENANT_NAME"

else
    dos.py list
    echo "============================================================"
    echo "Usage: $0 <env>"
fi
