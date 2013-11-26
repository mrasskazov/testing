#!/bin/bash -x

export TOP_DIR=$(cd $(dirname "$0") && pwd)

export JOB_NAME=${1:-tempest-fuel-4.0-auto}
export JENKINS_URL="http://osci-jenkins.srt.mirantis.net:8080"
export JENKINS_CLI="${TOP_DIR}/jenkins-cli.jar"

export NODE_XML="${TOP_DIR}/node_me.xml"
[ -f "$NODE_XML" ] || ${TOP_DIR}/prep_node_xml.py > $NODE_XML
export NODE_NAME=$(awk -F'[ <>]' '/\<name\>/ {print $5}' $NODE_XML)


create-node(){
    cat $NODE_XML | java -jar $JENKINS_CLI -s $JENKINS_URL create-node
    java -jar $JENKINS_CLI -s $JENKINS_URL wait-node-online $NODE_NAME
}


delete-node(){
    java -jar $JENKINS_CLI -s $JENKINS_URL delete-node $NODE_NAME
}


build-job(){
    NODE_NAME=$(awk -F'[ <>]' '/\<name\>/ {print $5}' ${TOP_DIR}/node_me.xml)

    java -jar $JENKINS_CLI -s $JENKINS_URL build ${JOB_NAME} -p NODE_NAME=${NODE_NAME} -s
}


wget -O ${JENKINS_CLI} -c "${JENKINS_URL}/jnlpJars/jenkins-cli.jar"
create-node && build-job && delete-node
