#!/usr/bin/env python
#-*- coding: utf-8 -*-


import socket
import fcntl
import struct
import os
import json
from pprint import pprint


from systests.nailgun_client import NailgunClient
import systests.http


def get_ip_address(ifname):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    return socket.inet_ntoa(fcntl.ioctl(
        s.fileno(), 0x8915, struct.pack('256s', ifname[:15]))[20:24])


def shell_cmd(cmd):
    print 'SHELL: ' + cmd
    return os.popen(cmd)


def iface_config(iface, ip):
    cmd = 'sudo ip addr add %s dev %s' % (ip, iface)
    return shell_cmd(cmd)


def iface_up(iface):
    cmd = 'sudo ifconfig %s up' % (iface, )
    return shell_cmd(cmd)


def config_vlan(iface, id):
    cmd = 'sudo vconfig add %s %s' % (iface, id)
    return shell_cmd(cmd)


def main():

    top_dir = os.path.abspath(os.path.dirname(__file__))
    home_dir = os.getenv('HOME', '/home/jenkins')

    with open(os.path.join(home_dir, 'node_init.json'), 'r') as inf:
        env_cfg = json.load(inf)

    #up admin network
    admin_net = [_ for _ in env_cfg['node']['networks']
                 if _['name'] == 'admin'][0]
    admin_ip = '/'.join((admin_net['ip'],
                         (admin_net['ip_network'].split('/')[1])))
    iface_config('eth1', admin_ip)
    iface_up('eth1')

    nc = NailgunClient(env_cfg['nailgun']['ip_address'])
    cluster = nc.list_clusters()[0]
    cluster_id = cluster['id']
    #cluster_id = nc.get_cluster_id(cluster_name)
    #cluster = nc.get_cluster(cluster_id)
    nets = nc.get_networks(cluster_id)
    for net in env_cfg['node']['networks']:
        if net['name'] not in ['br0', 'admin', 'floating']:
            pprint('%s' % (str(net)))
            nnet = [_ for _ in nets['networks'] if _['name'] == net['alias']][0]
            pprint('%s' % (str(nnet)))
            iface = net['iface']
            if nnet['vlan_start'] is not None:
                vlan_id = nnet['vlan_start']
                config_vlan(iface, vlan_id)
                iface = '%s.%d' % (iface, vlan_id)
            ip = '/'.join((net['ip'],
                          (net['ip_network'].split('/')[1])))
            iface_config(iface, ip)
            iface_up(iface)

    #pprint(nc.list_clusters())
    #pprint(nc.get_root)

    #get network config for other networks (excluding br0 and admin)
    #up other networks

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
