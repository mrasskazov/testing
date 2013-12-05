#!/usr/bin/env python

#    Copyright 2013 Mirantis, Inc.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.


import ipaddr
import argparse
import os
import shutil
import json
import logging


import nbd_wrapper as nbd
from systests.decorators import debug, json_parse


logger = logging.getLogger(__name__)
logwrap = debug(logger)


iface_aliases = {
    'admin': 'fuelweb_admin',
    'public': 'public',
    'floating': 'floating',
    'management': 'management',
    'storage': 'storage',
    'private': 'fixed',
}


def _safe_get_bridge(manager, environment, br_name):
    # connect to external network via host bridge
    #def network_create(
    #    self, name, environment=None, ip_network=None, pool=None,
    #    has_dhcp_server=True, has_pxe_server=False,
    #    forward='nat'
    #):
    #forward = choices(
    #    'nat', 'route', 'bridge', 'private', 'vepa',
    #    'passthrough', 'hostdev', null=True)
    try:
        return environment.network_by_name(br_name)
    except Exception as e:
        print e
        return manager.network_create(environment=environment,
                                      name=br_name,  # name of the host bridge
                                                     # to connect
                                      ip_network=True,
                                      forward='hostdev')


def insert_to_file(infile, line, template=None, number=None, replace=False):
    outfile_name = infile.name + '.tmp'
    with open(outfile_name, 'w') as outfile:
        for inline in infile:
            if template is not None:
                if inline.startswith(template):
                    outfile.write(line)
                outfile.write(inline)
    shutil.move(outfile_name, infile.name)


def add_node(manager, env_name, node_name, template_volume):
    try:
        environment = manager.environment_get(env_name)
    except:  # Exception as e:
        pass
        #print e
        #exit(1)

    admin_node = environment.node_by_name('admin')
    admin_ip = admin_node.get_ip_address_by_network_name('admin')

    try:
        tempest_node = manager.node_create(name=node_name,
                                           environment=environment,
                                           boot=['hd'])
    except:  # Exception as e:
        pass
        #print e
        ## tempest_node = environment.node_by_name(name=node_name)
        #exit(2)

    br_net = _safe_get_bridge(manager, environment,
                              os.get_env('HOST_BRIDGE', 'br0'))

    # TODO: implement create_or_get to host networks

    #def interface_create(self, network, node, type='network',
    #                     mac_address=None, model='virtio'):
    manager.interface_create(node=tempest_node,
                             network=br_net,
                             type='bridge')

    job_params = os.getenv('JENKINS_JOB_PARAMS', None)
    if job_params is not None:
        job_params = json.load(job_params)

    cfg = {
        'jenkins': {
            'url': os.getenv('JENKINS_URL',
                             'http://osci-jenkins.srt.mirantis.net:8080'),
            # 'keys':
            'JOB_NAME': os.getenv('JENKINS_JOB_NAME',
                                  'tempest-fuel-3.2-auto'),
            'JOB_PARAMS': job_params,
        },
        'environment': {
            'name': environment.name,
        },
        'nailgun': {
            'ip_address': admin_ip,
        },
        'node': {
            'name': tempest_node.name,
            'networks': [
                {
                    'iface': 'eth0',
                    'name': br_net.name,
                    'alias': None,
                    'ip_network': br_net.ip_network,
                    'ip': None,
                },
            ]
        }
    }

    # connect to internal network
    for net in environment.networks:
        if net.name != br_net.name:
            try:
                # env_net = environment.network_by_name('management')
                manager.interface_create(node=tempest_node, network=net)
                ip = tempest_node.get_ip_address_by_network_name(net.name)
                cfg['node']['networks'].append(
                    {
                        'iface': 'eth' + str(len(cfg['node']['networks'])),
                        'name': net.name,
                        'alias': iface_aliases[net.name],
                        'ip_network': net.ip_network,
                        'ip': str(ip),
                    })
            except:  # Exception as e:
                pass
                #print e
                #exit(3)

    logger.info('NODE_CONFIG: %s' % (json.dumps(cfg)))
    # create and connect volume
    vol_tpl = manager.volume_get_predefined(template_volume)
    vol_base = manager.volume_create_child(node_name + 'test_vol',
                                           backing_store=vol_tpl,
                                           environment=environment)
    manager.node_attach_volume(node=tempest_node, volume=vol_base)

    vol_base.define()

    # data injection
    dev = nbd.connect(vol_base.get_path(), read_only=False)
    mount_path = nbd.mount(dev)

    shutil.copy2('node_prepare/node_init.sh',
                 os.sep.join((mount_path, 'home/jenkins')))

    file_name = 'home/jenkins/node_init'
    #with open(os.sep.join((mount_path, file_name + '.yaml')), 'w') as f:
    #    yaml.safe_dump(cfg, f)
    with open(os.sep.join((mount_path, file_name + '.json')), 'w') as f:
        f.write(json.dumps(cfg, indent=4, separators=(',', ':')))

    #with open(os.sep.join((mount_path, 'etc/rc.local')), 'r') as f:
    #    insert_to_file(f,
    #                   'sudo -i -u jenkins /home/jenkins/node_init.sh',
    #                   template='exit 0')

    nbd.disconnect(dev)

    tempest_node.define()
    tempest_node.start()
    exit()


def create_env(manager):
    environment = manager.environment_create(env_name)
    private_pool = manager.create_network_pool(
        networks=[ipaddr.IPNetwork('10.108.0.0/16')], prefix=24
    )
    internal_pool = manager.create_network_pool(
        networks=[ipaddr.IPNetwork('10.108.1.0/16')], prefix=24
    )
    external_pool = manager.create_network_pool(
        networks=[ipaddr.IPNetwork('172.18.95.0/24')], prefix=27
    )
    admin = manager.network_create(
        environment=environment, name='admin', pool=private_pool)
    internal = manager.network_create(
        environment=environment, name='internal', pool=internal_pool)
    external = manager.network_create(
        environment=environment, name='external', pool=external_pool,
        forward='nat')
    for i in ('admin', 'slave-01'):
        node = manager.node_create(name=i,
                                   environment=environment,
                                   boot=['hd'])
        manager.interface_create(node=node, network=internal)
        manager.interface_create(node=node, network=external)
        manager.interface_create(node=node, network=admin)
        volume = manager.volume_get_predefined(
            '/media/build/libvirt_default/vm_tempest_template.img')
            #'/var/lib/libvirt/images/vm_ubuntu_initial.img')
            #'/media/build/libvirt_default/vm_ubuntu_initial.img')
            #'/var/lib/libvirt/images/vm_tempest_template.img')
        v3 = manager.volume_create_child('test_vp895' + i,
                                         backing_store=volume,
                                         environment=environment)
        #v4 = manager.volume_create_child('test_vp896' + i,
                                          #backing_store=volume,
                                          #environment=environment)
        manager.node_attach_volume(node=node, volume=v3)
        #manager.node_attach_volume(node, v4)
    environment.define()
    environment.start()
    exit()

    remotes = []
    for node in environment.nodes:
        node.await('external')
        hostname = ('%s-%s' % (node.name, env_name)).replace('_', '-')
        print(hostname)
        node.remote('external',
                    'jenkins',
                    'jenkins').check_stderr(
                        'sudo hostname %s; '
                        #'sudo sed -i "s|osci-tempest|%s|g" /etc/hosts; '
                        'ifconfig eth0 | grep "inet addr";' %
                        (hostname, ),
                        verbose=True)
        remotes.append(node.remote('external', 'jenkins', 'jenkins'))
        #node.remote('external',
                     #'root',
                     #'r00tme').check_stderr('ls -la', verbose=True)
        #remotes.append(node.remote('external', 'root', 'r00tme'))
    #SSHClient.execute_together(remotes, 'hostname -f; ifconfig eth0')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Create environment or add'
                                     'VM to environment created via devops.')
    parser.add_argument('command',
                        choices=['create-env', 'add-node'],
                        help='command')
    parser.add_argument('-e', '--env-name',
                        help='name of the environment to create')
    parser.add_argument('-n', '--name',
                        help='name of the VM to create')
    args = parser.parse_args()

    env_name = args.env_name
    node_name = args.name

    template_volume = '/media/build/libvirt_default/vm_tempest_template.img'
    #template_volume = '/media/build/libvirt_default/vm_ubuntu_initial.img'
    #template_volume = '/var/lib/libvirt/images/vm_ubuntu_initial.img'
    #template_volume = '/var/lib/libvirt/images/vm_tempest_template.img'

    from devops.manager import Manager
    if args.command == 'create-env':
        create_env(Manager())
    elif args.command == 'add-node':
        add_node(Manager(), env_name, node_name, template_volume)
