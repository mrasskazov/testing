#!/usr/bin/env python
#-*- coding: utf-8 -*-


import socket
import fcntl
import struct
import os


def get_ip_address(ifname):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    return socket.inet_ntoa(fcntl.ioctl(
        s.fileno(), 0x8915, struct.pack('256s', ifname[:15]))[20:24])


def main():

    top_dir = os.path.abspath(os.path.dirname(__file__))

    try:
        host = get_ip_address(os.getenv('JENKINS_IFACE', 'eth0'))
    except IOError:
        exit(1)

    params = {
        'host': host,
        'name': 'tempest-%s' % (host.replace('.', '-')),
    }

    template = open(os.getenv('NODE_TPL',
                              os.sep.join((top_dir, 'node_xml.tpl'))),
                    'r').read()

    print template % (params)
    return 0


if __name__ == '__main__':
    main()
