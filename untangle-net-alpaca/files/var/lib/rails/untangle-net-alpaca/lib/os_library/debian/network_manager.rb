class OSLibrary::Debian::NetworkManager < OSLibrary::NetworkManager
  include Singleton

  Service = "/etc/init.d/networking"
  InterfacesConfigFile = "/etc/network/interfaces"
  InterfacesStatusFile = "/etc/network/run/ifstate"
  IfTabConfigFile = "/etc/network/run/ifstate"

  def interfaces
    logger.debug( "Running inside of the network manager for debian" )

    interfaceArray = []

    devices=`find /sys/devices -name 'net:*' | sed 's|.*net:||'`

    devices.each do |os_name|
      os_name = os_name.strip

      bus_id=""
      vendor=get_vendor( os_name )

      ## For some reason, on some systems this causes ruby to hang, use 'cat' instead.
      # mac_address = File.open( "/sys/class/net/#{os_name}/address", "r" ) { |f| f.readline.strip }
      mac_address = `cat "/sys/class/net/#{os_name}/address"`.strip
      
      interfaceArray << PhysicalInterface.new( os_name, mac_address, bus_id, vendor )
    end
    
    interfaceArray
  end

  def hook_commit
    write_files
    run_services
  end

  def hook_write_files
    interfaces_file = []
    interfaces_file << header
    
    interfaces = Interface.find( :all )
    interfaces.each do |interface|
      config = interface.current_config
      ## REVIEW refactor me.
      case config
      when IntfStatic
        interfaces_file << static( interface, config )
      when IntfDynamic
        interfaces_file << dynamic( interface, config )
      when IntfBridge
        interfaces_file << bridge( interface, config )
      when IntfPppoe
        interfaces_file << pppoe( interface, config )
      end
    end

    interfaces_file.push <<EOF
## This will run any scripts that need to execute when the address changes.
auto update
iface update inet manual

EOF

    ## Delete all empty or nil parts
    interfaces_file = interfaces_file.delete_if { |p| p.nil? || p.empty? }

    os["override_manager"].write_file( InterfacesConfigFile, interfaces_file.join( "\n" ), "\n" )

    ## Write the /etc/iftab file, ifrename is not executed
    ## Review : now because we no longer need to remap interfaces
    ## furthermore, udev is kind enough to handle this automatically.

    ## Clear out all of the interface state.
    ## Review: Should this be immutable.
    File.open( InterfacesStatusFile, "w" ) { |f| f.print( "lo=lo" ) }
  end

  def hook_run_services
    ## Restart networking
    raise "Unable to reconfigure network settings." unless run_command( "sh #{Service} start" ) == 0
  end

  ## Given an interface, this returns the expected bridge name
  def self.bridge_name( interface )
    "br.#{interface.os_name}"
  end

  private

  ## Dump out the configuration for a statically configured interface.
  def static( interface, static )
    i = nil

    ## name of the interface
    name = interface.os_name
    
    if static.nil?
      logger.warn( "The interface #{interface} is not configured" )
      return ""
    end

    ## Copy the array of ip_networks
    ip_networks = [ static.ip_networks ].flatten

    ## This will automatically remove the first ip_network if it is assigned to the bridge.
    bridge = bridgeSettings( interface, static.mtu, "manual", ip_networks )
    
    mtu = mtuSetting( static.mtu )

    gw = static.default_gateway
    gateway_string = ""
    if ( interface.wan && !gw.nil? && !gw.empty? )
      gateway_string = "\tgateway #{static.default_gateway}\n" 
    end
    
    ## set the name
    ## Clear the MTU because that is set in the bridge
    name, mtu = OSLibrary::Debian::NetworkManager.bridge_name( interface ), nil unless bridge.empty?
    
    ## Configure each IP and then join it all together with some newlines.
    bridge += "\n" + append_ip_networks( ip_networks, name, mtu, !bridge.empty? )

    ## Append the gateway at the end, this way if one of the aliases
    ## is routed to the gateway it will still work.
    bridge + gateway_string
  end

  def dynamic( interface, dynamic )
    ## REVIEW this is the first area that requires managers for separate files.
    ## this is updated in /etc/network/interfaces.
    ## The hostname may be modified here, or in /etc/dhcp3/dhclient.conf, ...
    ## overrides definitely go in /etc/dhcp3/dhclient.conf
    ## Default gateway override settings?

    ## REVIEW what should timeout be on configuring the interface

    i = nil

    ## name of the interface
    name = interface.os_name
    
    if dynamic.nil?
      logger.warn( "The interface #{interface} is not configured" )
      return ""
    end
    
    ## assume it is a bridge until determining otherwise
    name = OSLibrary::Debian::NetworkManager.bridge_name( interface )
    
    base_string = bridgeSettings( interface, dynamic.mtu, "dhcp" )

    ## REVIEW MTU Setting doesn't do anything in this case.
    if base_string.empty?
      name = interface.os_name
      base_string  = <<EOF
auto #{name}
iface #{name} inet dhcp
#{mtuSetting( dynamic.mtu )}
EOF
    end

    ## never set the mtu, and always start with an alias.
    base_string + "\n" + append_ip_networks( dynamic.ip_networks, name, nil, true )
  end

  def bridge( interface, bridge )
    logger.debug( "Nothing needed for a bridge interface" )
    ""
  end

  ## These are the settings that should be appended to the first
  ## interface index that is inside of the interface (if this is in fact a bridge)
  def bridgeSettings( interface, mtu, config_method, ip_networks = []  )
    ## Check if this is a bridge
    bridged_interfaces = interface.bridged_interfaces
    
    ## Create a new set of bridged interfaces
    bridged_interfaces = bridged_interfaces.map { |ib| ib.interface }
    
    ## Delete all of the nil interfaces and the ones where the bridge type isn't set properly.
    bridged_interfaces = bridged_interfaces.delete_if do |ib| 
      ib.nil? || ib.config_type != InterfaceHelper::ConfigType::BRIDGE
    end

    ## If this is nil or empty, it is not a bridge.    
    return "" if ( bridged_interfaces.nil? || bridged_interfaces.empty? )
    
    ## Append this interface
    bridged_interfaces << interface

    bridge_name = self.class.bridge_name( interface )

    ## The bridge is configured as br.<intf> and then all of the ips
    ## are configured as br.<intf>:0 - done this way so restart
    ## doesn't call ifconfig br.intf down, if this happens the
    ## bridge has to relearn creating 30seconds of down time.

    configuration = <<EOF
auto #{bridge_name}
iface #{bridge_name} inet #{config_method}
\talpaca_bridge_ports #{bridged_interfaces.map{ |i| i.os_name }.join( " " )}
\talpaca_debug true
\tbridge_ageing 900
#{mtuSetting( mtu, "alpaca_bridge_" )}
EOF

    unless ip_networks.empty?
      ## Append the configuration for the first item
      primary_network = ip_networks.delete_at(0)
      configuration += <<EOF
\taddress #{primary_network.ip}
\tnetmask #{OSLibrary::NetworkManager.parseNetmask( primary_network.netmask)}
EOF
    end

    return configuration
  end

  def pppoe( interface, pppoe )
    ## REVIEW this is the first area that requires managers for separate files.
    ## this is updated in /etc/network/interfaces.
    ## Default gateway override settings?

    ## REVIEW what should timeout be on configuring the interface

    i = nil

    ## name of the interface
    name = interface.os_name
    
    if pppoe.nil?
      logger.warn( "The interface #{interface} is not configured" )
      return ""
    end
    
    base_string  = <<EOF
auto #{name}
iface #{name} inet manual
\tup poff -a
\tup pon #{OSLibrary::PppoeManager::PeersFilePrefix}-#{name}
EOF

    base_string
  end


  def append_ip_networks( ip_networks, name, mtu_string, start_with_alias )
    ## this determines whether the indexing should start with an alias.
    ## mtu never applies to an alias.
    i, mtu_string = ( start_with_alias ) ? [ 0, nil ] : [ nil, mtu_string ]

    ip_networks.map do |ip_network|
      ip_network_name = "#{name}#{i.nil? ? "" : ":#{i}"}"
      i = i.nil? ? 0 : i + 1
      
      base = <<EOF
auto #{ip_network_name}
iface #{ip_network_name} inet static
\taddress #{ip_network.ip}
\tnetmask #{OSLibrary::NetworkManager.parseNetmask( ip_network.netmask)}
EOF

      base += mtu_string + "\n" unless mtu_string.nil?
      mtu_string = nil
      
      base
    end.join( "\n" )
  end

  ## mtu is always set, just in case the user overrides it
  def mtuSetting( mtu, prefix = "" )
    ## MTU of 0 or less is ignored
    mtu = OSLibrary::NetworkManager::DefaultMTU if ( mtu.nil? || mtu <= 0 )

    return "\t#{prefix}mtu #{mtu}"
  end

  def get_vendor( os_name )
    path="/sys/class/net/#{os_name}/device/uevent"
    bus,vendor_id = `awk '/(PHYSDEVBUS|PCI_ID|PRODUCT)/ { sub( /^[^=]*=/, "" );  print $0 }' #{path}`.strip.split( "\n" )
    
    return "Unknown" if ApplicationHelper.null?( vendor_id ) || ApplicationHelper.null?( bus )

    vendor_id = vendor_id.sub( /[:\/].*/, "" )
    
    case bus
    when "usb"
      vendor = `zcat /usr/share/misc/usb.ids | awk '/^#{vendor_id}/ { $1 = "" ; print $0 }'`.strip
    when "pci"
      vendor = `awk '/^#{vendor_id}/ { $1 = "" ; print $0 }' /usr/share/misc/pci.ids`.strip
    else return "Unknown"
    end
    
    return "Unknown" if ApplicationHelper.null?( vendor )
    return vendor
  end

  def header
    <<EOF
## #{Time.new}
## Auto Generated by the Untangle Net Alpaca
## If you modify this file manually, your changes
## may be overriden

## This causes a script to tear down any bridges that are not necessary.
auto cleanup
iface cleanup inet manual
\talpaca_debug true

## Configuration for the loopback interface
auto lo
iface lo inet loopback

EOF
  end
end
