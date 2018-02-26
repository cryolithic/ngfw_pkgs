import os
import pwd
import grp
import sys
import subprocess
import datetime
import traceback
import re
from shutil import move
from netd.network_util import NetworkUtil

# This class is responsible for writing 
# based on the settings object passed from sync-settings.py
class DynamicRoutingManager:
    confPath="/etc/quagga"
    daemonsConfFilename=confPath + "/daemons"
    zebraConfFilename=confPath + "/zebra.conf"
    bgpdConfFilename=confPath + "/bgpd.conf"
    ospfdConfFilename=confPath + "/ospfd.conf"
    file_uid=pwd.getpwnam("quagga").pw_uid
    file_gid=grp.getgrnam("quagga").gr_gid

    autoGeneratedComment="Auto Generated"
    doNotEditComment="DO NOT EDIT. Changes will be overwritten"

    hostname="Router"
    password="zebra"

    allowed_daemons = ["bgp", "ospf"]

    restartHookFilename = "/etc/untangle-netd/post-network-hook.d/990-restart-quagga"
    ip_dev_regex = re.compile(r'\s+dev\s+([^\s]+)')
    # ?? supprt inet6?
    ip_addr_regex = re.compile(r'\s+inet\s+([^\s]+)')

    def address_to_bits(address):
        return ''.join('{:08b}'.format(int(x)) for x in address.split('.'))

    def bits_to_address(bits, prefix):
        chunks = len(bits)
        chunk_size = chunks/4
        return '.'.join([ '{0}'.format(int(bits[i:i+chunk_size], 2)) for i in range(0, chunks, chunk_size)])

    def get_interfaces_from_networks(self, settings, want_daemon=None):
        interfaces = []

        # Look at bgp + ospf networks
        # look at interfaces to get best route match:
        # interfaces
        # openvpn
        # tunnelvpn
        #

        # Build explicitly define network list for specified daemon.
        # If daemon is not defined, pull from all daemons (used in Zebra)
        #
        networks = []
        for daemon in self.allowed_daemons:
            if want_daemon is not None and want_daemon is not daemon:
                continue

            if settings["dynamicRoutingSettings"]:
                if ( settings["dynamicRoutingSettings"][daemon+"Enabled"] and 
                     settings["dynamicRoutingSettings"][daemon+"Networks"] and
                    settings["dynamicRoutingSettings"][daemon+"Networks"]["list"]):
                    for networkSetting in settings["dynamicRoutingSettings"][daemon+"Networks"]["list"]:
                        if networkSetting["enabled"]:
                            network = networkSetting["network"] + "/" + str(networkSetting["prefix"])
                            if not network in networks:
                                networks.append({
                                    "network": network,
                                    "found": False
                                })

        for network in networks:
            network_net, netmask_bits = network["network"].split('/')
            netmask_bits = int(netmask_bits)
            network_bits = ''.join('{:08b}'.format(int(x)) for x in network_net.split('.'))

            # print network_net_bits
            # print network_net_bits[:netmask_bits]
            if settings["interfaces"] and settings["interfaces"]["list"]:
                for interface in settings["interfaces"]["list"]:
                    if interface["configType"] == "ADDRESSED" and interface["v4ConfigType"] == "STATIC":
                        i_netmask_bits = interface["v4StaticPrefix"]
                        i_network_bits = ''.join('{:08b}'.format(int(x)) for x in interface["v4StaticAddress"].split('.'))
                        if netmask_bits <= i_netmask_bits and network_bits[:i_netmask_bits] == i_network_bits[:i_netmask_bits]:
                            dev_object = {
                                'dev': interface["symbolicDev"],
                                'address': interface["v4StaticAddress"],
                                'prefix': interface["v4StaticPrefix"]
                            }
                            network["found"] = True
                            if not dev_object in interfaces:
                                interfaces.append(dev_object)
                            network["found"] = True
                    if interface["configType"] == "ADDRESSED" and interface["v4Aliases"] and interface["v4Aliases"]["list"]:
                        for alias in interface["v4Aliases"]["list"]:
                            i_netmask_bits = alias["staticPrefix"]
                            i_network_bits = ''.join('{:08b}'.format(int(x)) for x in alias["staticAddress"].split('.'))
                            if netmask_bits <= i_netmask_bits and network_bits[:i_netmask_bits] == i_network_bits[:i_netmask_bits]:
                                dev_object = {
                                    'dev': interface["symbolicDev"],
                                    'address': alias["staticAddress"],
                                    'prefix': alias["staticPrefix"]
                                }
                                network["found"] = True
                                if not dev_object in interfaces:
                                    interfaces.append(dev_object)

            if network["found"] is False:
                for route in subprocess.Popen("ip route show {0}".format(network["network"]), shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT).communicate()[0].split('\n'):
                    match_dev = re.search( self.ip_dev_regex, route )
                    if match_dev:
                        dev = match_dev.group(1)
                        for addr in subprocess.Popen("ip addr show dev {0}".format(dev), shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT).communicate()[0].split('\n'):
                            match_addr = re.search( self.ip_addr_regex, addr )
                            if match_addr:
                                dev_network_addr, dev_network_prefix = match_addr.group(1).split('/')
                                dev_object = {
                                    'dev': dev,
                                    'address': dev_network_addr,
                                    'prefix': dev_network_prefix
                                }
                                if not dev_object in interfaces:
                                    interfaces.append( dev_object )
                                break

        return interfaces

    def write_daemons_conf( self, settings, prefix="", verbosity=0 ):
        """
        Create Quagga daemon configuration file.
        """
        filename = prefix + self.daemonsConfFilename
        fileDir = os.path.dirname( filename )
        if not os.path.exists( fileDir ):
            os.makedirs( fileDir )

        enables = {
            'zebra': False,
            'bgpd': False,
            'ospfd': False
        }
        enables['zebra'] = settings['dynamicRoutingSettings']['enabled']
        if enables['zebra']:
            enables['bgpd']= settings['dynamicRoutingSettings']['bgpEnabled']
            enables['ospfd'] = settings['dynamicRoutingSettings']['ospfEnabled']

        # Daemon file is supplied by package, so "modify" by reading live instead of overwriting.
        daemons_contents = []
        file = open(self.daemonsConfFilename, "r")
        for line in file:
            line = line.strip()
            if line == "":
                continue
            elif line.startswith('#'):
                if self.autoGeneratedComment in line:
                    continue
                if self.doNotEditComment in line:
                    continue
                daemons_contents.append(line)
            elif "=" in line:
                [daemon,currently_enabled] = line.split("=", 2)
                if daemon in enables:
                    daemons_contents.append("{0}={1}".format(daemon, 'yes' if enables[daemon] is True else 'no'))
                else:
                    daemons_contents.append(line)
            else:
                daemons_contents.append(line)
        file.close()

        file = open( filename, "w+" )
        file.write("## {0}{1}".format(self.autoGeneratedComment, "\n"));
        file.write("## {0}{1}".format(self.doNotEditComment, "\n"));
        for line in daemons_contents:
            file.write(line + "\n")

        file.flush()
        file.close()
        os.chown(filename, self.file_uid, self.file_gid)

        if verbosity > 0: print "DynamicRoutingManager: Wrote %s" % filename

    def write_zebra_conf( self, settings, prefix="", verbosity=0 ):
        """
        Create Quagga zebra daemon configuration file.
        """
        enabled = settings['dynamicRoutingSettings']['enabled']
        if not enabled:
            return

        filename = prefix + self.zebraConfFilename
        fileDir = os.path.dirname( filename )
        if not os.path.exists( fileDir ):
            os.makedirs( fileDir )

        zebra_interfaces = []
        for interface in self.get_interfaces_from_networks(settings):
            zebra_interfaces.append("""
interface {0}
 ip address {1}/{2}
 ipv6 nd suppress-ra
""".format(interface["dev"], interface["address"], interface["prefix"]))

        file = open( filename, "w+" )
        file.write(r"""
! {0}
! {1}
hostname {2}
password {3}
enable password {3}

{4}

ip forwarding
line vty
""".format(self.autoGeneratedComment, self.doNotEditComment, self.hostname, self.password, "\n".join(zebra_interfaces) ))

        file.write("\n");
        file.flush()
        file.close()
        os.chown(filename, self.file_uid, self.file_gid)

        if verbosity > 0: print "DynamicRoutingManager: Wrote %s" % filename

    def write_bgpd_conf( self, settings, prefix="", verbosity=0 ):
        """
        Create Quagga bgp daemon configuration file.
        """
        enabled = settings['dynamicRoutingSettings']['enabled'] and settings['dynamicRoutingSettings']['bgpEnabled']
        if not enabled:
            return

        filename = prefix + self.bgpdConfFilename
        fileDir = os.path.dirname( filename )
        if not os.path.exists( fileDir ):
            os.makedirs( fileDir )

        bgp_networks = []
        if settings['dynamicRoutingSettings']['bgpNetworks'] and settings['dynamicRoutingSettings']['bgpNetworks']["list"]:
            for network in settings['dynamicRoutingSettings']['bgpNetworks']["list"]:
                if network["enabled"] is True:
                    bgp_networks.append("network {0}/{1}".format(network["network"], network["prefix"]) )

        bgp_neighbors = []
        if settings['dynamicRoutingSettings']['bgpNeighbors'] and settings['dynamicRoutingSettings']['bgpNeighbors']["list"]:
            for neighbor in settings['dynamicRoutingSettings']['bgpNeighbors']["list"]:
                if neighbor["enabled"] is True:
                    bgp_neighbors.append("""
neighbor {0} remote-as {1}
neighbor {0} route-map set-nexthop out
neighbor {0} ebgp-multihop
neighbor {0} next-hop-self
""".format(neighbor["ipAddress"], neighbor["as"]) )

        file = open( filename, "w+" )
        file.write(r"""
! {0}
! {1}
hostname bgpd
password {2}
enable password {2}

router bgp {3}
bgp router-id {4}

{5}

{6}

route-map set-nexthop permit 10
""".format(self.autoGeneratedComment, self.doNotEditComment, self.password, settings['dynamicRoutingSettings']['bgpRouterAs'], settings['dynamicRoutingSettings']['bgpRouterId'], "\n".join(bgp_networks), "\n".join(bgp_neighbors) ))

        file.write("\n");
        file.flush()
        file.close()
        os.chown(filename, self.file_uid, self.file_gid)

        if verbosity > 0: print "DynamicRoutingManager: Wrote %s" % filename

    def write_ospfd_conf( self, settings, prefix="", verbosity=0 ):
        """
        Create Quagga ospf daemon configuration file.
        """
        enabled = settings['dynamicRoutingSettings']['enabled'] and settings['dynamicRoutingSettings']['ospfEnabled']
        if not enabled:
            return

        filename = prefix + self.ospfdConfFilename
        fileDir = os.path.dirname( filename )
        if not os.path.exists( fileDir ):
            os.makedirs( fileDir )

        ospf_interfaces = []
        for interface in self.get_interfaces_from_networks(settings, "ospf"):
            ospf_interfaces.append("interface {0}".format(interface["dev"]) )

        ospf_areas = {}
        if settings['dynamicRoutingSettings']['ospfAreas'] and settings['dynamicRoutingSettings']['ospfAreas']["list"]:
            for area in settings['dynamicRoutingSettings']['ospfAreas']["list"]:
                ospf_areas[area["ruleId"]] = area["area"]

        ospf_networks = []
        if settings['dynamicRoutingSettings']['ospfNetworks'] and settings['dynamicRoutingSettings']['ospfNetworks']["list"]:
            for network in settings['dynamicRoutingSettings']['ospfNetworks']["list"]:
                if network["enabled"] is True:
                    ospf_networks.append(" network {0}/{1} area {2}".format(network["network"], network["prefix"], ospf_areas[network["area"]]) )

        file = open( filename, "w+" )
# passive-interface {6}
        file.write(r"""
! {0}
! {1}
hostname ospfd
password {2}
enable password {2}

log stdout

{5}

router ospf
{7}

route-map set-nexthop permit 10
""".format(self.autoGeneratedComment, self.doNotEditComment, self.password, settings['dynamicRoutingSettings']['bgpRouterAs'], settings['dynamicRoutingSettings']['bgpRouterId'], "\n".join(ospf_interfaces), 'devwhat', "\n".join(ospf_networks) ))

        file.write("\n");
        file.flush()
        file.close()
        os.chown(filename, self.file_uid, self.file_gid)

        if verbosity > 0: print "DynamicRoutingManager: Wrote %s" % filename

    def write_restart_quagga_daemons_hook( self, settings, prefix="", verbosity=0 ):
        """
        Create network process extension to restart or stop daemon
        """
        filename = prefix + self.restartHookFilename
        fileDir = os.path.dirname( filename )
        if not os.path.exists( fileDir ):
            os.makedirs( fileDir )

        file = open( filename, "w+" )
        file.write("#!/bin/dash");
        file.write("\n\n");

        file.write("""
## {0}
## {1} 

""".format(self.autoGeneratedComment, self.doNotEditComment))

        # !!! look for enabled with dictionary check
        if settings['dynamicRoutingSettings']['enabled'] is False:
            file.write(r"""
ZEBRA_PID="`pidof zebra`"

# Stop quagga if running
if [ ! -z "$ZEBRA_PID" ] ; then
    service quagga stop
fi
""")
        else:
            file.write(r"""
ZEBRA_PID="`pidof zebra`"

# Restart quagga if it isnt found
# Or if zebra.conf orhas been written since quagga was started
if [ -z "ZEBRA_PID" ] ; then
    service quagga restart
# use not older than (instead of newer than) because it compares seconds and we want an equal value to still do a restart
elif [ ! {0} -ot /proc/$ZEBRA_PID ] ; then
    service quagga restart
fi
""".format(self.daemonsConfFilename))

        file.write("\n");
        file.flush()
        file.close()
    
        os.system("chmod a+x %s" % filename)
        if verbosity > 0: print "DynamicRoutingManager: Wrote %s" % filename
        return

    def sync_settings( self, settings, prefix="", verbosity=0 ):

        if verbosity > 1: print "DynamicRoutingManager: sync_settings()"

        self.write_daemons_conf( settings, prefix, verbosity )
        self.write_zebra_conf( settings, prefix, verbosity )
        self.write_bgpd_conf( settings, prefix, verbosity )
        self.write_ospfd_conf( settings, prefix, verbosity )
        self.write_restart_quagga_daemons_hook( settings, prefix, verbosity )

        return