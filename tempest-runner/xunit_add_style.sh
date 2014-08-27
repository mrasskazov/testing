#!/bin/bash

if [ "$1" = "" ]; then
    echo "Use: $0 <xml file with test results (xunit format)>"
    exit 1
fi
if [ ! -f "$1" ]; then
    echo "xml file '$1' not found."
    exit 2
fi

XML_FILE=$(readlink -f $1)
XML_PATH=$(dirname ${XML_FILE})
XSL_FILE="xunit.xsl"
if [ ! -f "${XML_PATH}/${XSL_FILE}" ]; then
    XSL_FILE_LINK="https://raw.githubusercontent.com/mrasskazov/testing/master/tempest-runner/xunit.xsl"
    wget -nv -P ${XML_PATH} ${XSL_FILE_LINK}
fi

if [ "$(grep -Eo "xml-stylesheet" ${XML_FILE})" == "" ]; then
    sed -ie '0,/\?>/ s[?>[?><?xml-stylesheet type="text/xsl" href="'$XSL_FILE'"?>[' "$XML_FILE"
fi
