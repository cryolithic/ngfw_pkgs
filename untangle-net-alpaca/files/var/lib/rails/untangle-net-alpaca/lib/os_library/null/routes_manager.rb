#
# $HeadURL: svn://chef/work/pkgs/untangle-net-alpaca/files/var/lib/rails/untangle-net-alpaca/lib/os_library/routes_manager.rb $
# Copyright (c) 2007-2008 Untangle, Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License, version 2,
# as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but
# AS-IS and WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE, TITLE, or
# NONINFRINGEMENT.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
#
class OSLibrary::Null::RoutesManager < OSLibrary::RoutesManager
  include Singleton

  Service = "/etc/init.d/networking"
  ConfigFile = "/etc/untangle-net-alpaca/routes"

  def get_active
    `netstat -rn | awk '/^[0-9]/ { if (( index( $8, "dummy" ) == 0 ) && ( index( $8, "utun" ) == 0 )) print $1 "," $3 "," $2 "," $8 }'`.split( "\n" ).map do |entry|
      g = ActiveRoute.new 
      
      g.target, g.netmask, g.gateway, g.interface = entry.split( "," )
      
      if OSLibrary::NetworkManager::NETMASK_TO_CIDR.key?( g.netmask )
        g.netmask = OSLibrary::NetworkManager::NETMASK_TO_CIDR[g.netmask] + " (" + g.netmask + ")"
      end

      g
    end
  end

  def register_hooks
    os["network_manager"].register_hook( -100, "routes_manager", "write_files", :hook_write_files )
  end
  
  def hook_commit
    write_files
    run_services
  end

  def hook_write_files
    ## Retrieve all of the routes that are defined in interfaces by
    ## bogus addresses that end in .0
    network_routes = get_interface_routes
    
    network_routes += [ NetworkRoute.find( :all ) ].flatten
    
    cfg = []

    network_routes.each do |network_route|
      target = network_route.target
      netmask = network_route.netmask
      gateway = network_route.gateway

      next if IPAddr.parse_ip( target ).nil?
      netmask = IPAddr.parse_netmask( netmask )
      next if network_route.is_a?( NetworkRoute ) && IPAddr.parse_ip( gateway ).nil?

      ## Automatically mask off the necessary bits
      target = IPAddr.parse( "#{target}/#{netmask}" )
      next if target.nil? || netmask.nil?

      if network_route.is_a?( InterfaceRoute )
        cfg << "route add -net #{target} netmask #{netmask} dev #{gateway}"
      else
        cfg << "route add -net #{target} netmask #{netmask} gw #{gateway}"
      end
    end
    
    os["override_manager"].write_file( ConfigFile, header, "\n", cfg.join( "\n" ), "\n" )
  end

  def hook_run_services
    ## Restart networking
    raise "Unable to reconfigure network and route settings." unless run_command( "#{Service} restart" ) == 0
  end

  def header
    <<EOF
#!/bin/bash
## #{Time.new}
## Auto Generated by the Untangle Net Alpaca
## If you modify this file manually, your changes
## may be overriden
EOF
  end

  def get_interface_routes
    interface_routes = []
    interfaces = Interface.find( :all )
    route_visitor = InterfaceRouteVisitor.new

    interfaces.each do |interface|
      if ! interface.nil? and ! interface.current_config.nil?
          interface_routes += interface.current_config.accept( interface, route_visitor )
      end
    end

    interface_routes
  end
  
  class InterfaceRouteVisitor < Interface::ConfigVisitor
    def intf_static( interface, config )
      ## Create a copy of the array.
      interface_routes( interface, config.ip_networks )
    end

    def intf_dynamic( interface, config )
      interface_routes( interface, config.ip_networks )
    end

    def intf_bridge( interface, config )
      []
    end

    def intf_pppoe( interface, config )
      interface_routes( interface, config.ip_networks )
    end

    ## This should be moved into a central place as something close is
    ## used in the network manager.
    def interface_routes( interface, ip_networks )
      bridged_interfaces = interface.bridged_interface_array
      os_name = interface.os_name
      os_name = "br.#{os_name}" if ( !bridged_interfaces.nil? && !bridged_interfaces.empty? )

      ## Copy the array of ip_networks
      ip_networks = [ ip_networks  ].flatten

      ## Copy all of the ip networks
      ip_networks = ip_networks.map { |i| i.clone }

      ## Remove any interfaces that are not valid.
      ip_networks.delete_if { |ip_network| !is_route_network?( ip_network ) }

      ## Convert to Interface Routes
      ip_networks.map { |ipn| InterfaceRoute.new( ipn, os_name ) }
    end
    
    def is_route_network?( ip_network )
      return false if ApplicationHelper.null?( ip_network.ip )
      return false if ApplicationHelper.null?( ip_network.netmask )

      return false if IPAddr.parse_ip( ip_network.ip ).nil?
      return false if IPAddr.parse_netmask( ip_network.netmask ).nil?

      return false if ( ip_network.ip == "0.0.0.0" || ip_network.ip == "255.255.255.255" )
      return false if ( ip_network.netmask == "0.0.0.0" )
      
      return true if /\.0$/.match( ip_network.ip )
      return true if /\.255$/.match( ip_network.ip )

      false
    end
    
  end


  ## All kinds of badness
  class InterfaceRoute
    def initialize( ip_network, os_name )
      @target = ip_network.ip
      @netmask = ip_network.netmask
      @gateway = os_name
    end

    attr_reader :target, :netmask, :gateway
  end
end
