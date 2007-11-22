class OSLibrary::Debian::DnsServerManager < OSLibrary::DnsServerManager
  include Singleton

  ## This is a script that only restarts DNS masq if absolutely necessary.
  StartScript = "/etc/untangle-net-alpaca/scripts/dnsmasq"
  ResolvConfFile = "/etc/resolv.conf"
  DnsMasqLeases = "/var/lib/misc/dnsmasq.leases"
  DnsMasqConfFile = "/etc/dnsmasq.conf"
  DnsMasqHostFile = "/etc/untangle-net-alpaca/dnsmasq-hosts"
  
  DefaultDomain = "local.domain"

  ## REVIEW : This should be done inside of a module for DNS masq and
  ## then the OS Manager would include the desired module.  This gets
  ## us support for multiple applications being supported by a single
  ## manager.

  ## Flag to specify the range of addresses to serve
  FlagRange = "dhcp-range"

  ## Minimum length of DHCP lease
  MinLeaseDuration = 60
  MaxLeaseDuration = 60 * 60 * 24 * 7
  DefaultDuration = 60 * 60 * 4

  ## Flag to localize queries
  FlagDnsLocalize = "localise-queries"

  ## Flag to specify the localdomain
  FlagDnsLocalDomain = "domain"

  ## Flag to specify to expand hosts
  FlagDnsExpandHosts = "expand-hosts"
  
  ## Flag to specify to use a separate /etc/ host file.
  FlagDnsHostFile = "addn-hosts"

  FlagDnsServer = "server"

  ## Flag to specify a DHCP host entry.
  FlagDhcpHost = "dhcp-host"

  ## Flag to specify a DHCP option like gateway or netmask.
  FlagOption = "dhcp-option"
  OptionGateway = "3"
  OptionNetmask = "1"

  def register_hooks
    os["network_manager"].register_hook( -200, "dns_server_manager", "write_files", :hook_write_files )
    os["network_manager"].register_hook( 200, "dns_server_manager", "run_services", :hook_run_services )

    ## Register with the hostname manager to update when there are
    ## changes to the hostname
    os["hostname_manager"].register_hook( 200, "dns_server_manager", "commit", :hook_commit )
  end

  def hook_commit
    write_files
    
    run_services
  end

  def hook_write_files
    write_resolv_conf

    ## Write the separate DNS Masq file that is used by dnsmasq
    write_dnsmasq_hosts

    write_dnsmasq_conf
  end
  
  ## Restart DNS Masq
  def hook_run_services
    raise "Unable to restart DNS Masq." unless Kernel.system( "sh #{StartScript} restart false" )
  end

  ## Sample entry
  ## 1193908192 00:0e:0c:a0:dc:a9 10.0.0.112 gobbleswin 01:00:0e:0c:a0:dc:a9
  def dynamic_entries
    entries = []
    ## Open up the dns-masq leases file and print create a table for each entry
    File.open( DnsMasqLeases ) do |f|
      f.each_line do |line|
        expiration, mac_address, ip_address, hostname, client_id = line.split( " " )
        next if ( hostname.nil? || hostname == "*" )
        entries << DynamicEntry.new( ip_address, hostname )
      end
    end
    entries.sort!
    entries
  end

  private

  def write_resolv_conf
    os["override_manager"].write_file( ResolvConfFile, <<EOF )
## #{Time.new}
## Auto Generated by the Untangle Net Alpaca
## If you modify this file manually, your changes
## may be overriden

## dns-masq handles all of the name resolution
nameserver 127.0.0.1
search #{domain_name_suffix}
EOF

    ## REVIEW: Need to get the search domain.

    ## REVIEW: This is a possible hook where something else would introduce or replace name servers.    
  end

  ## Configuration for dnsmasq.  This actually configures the DHCP server and the DNS Server.
  def write_dnsmasq_hosts
    h_file = []

    h_file << <<EOF
## #{Time.new}
## Auto Generated by the Untangle Net Alpaca
## If you modify this file manually, your changes
## may be overriden
EOF

    dns_server_settings = DnsServerSettings.find( :first )
    unless ( dns_server_settings.nil? || dns_server_settings.enabled )
      DnsStaticEntry.find(:all).each { |dse| h_file << "#{dse.ip_address} #{dse.hostname}" }
    end

    ## Append the hostname
    settings = HostnameSettings.find( :first )
    unless ( settings.nil? || settings.hostname.nil? || settings.hostname.empty? )
      h_file << "127.0.0.1 #{settings.hostname}"
    end

    os["override_manager"].write_file( DnsMasqHostFile, h_file.join( "\n" ), "\n" )

  end

  ## Review: Possibly move the writing of the file to another hook, because
  ## this has to run after being assigned a DHCP address.
  ## Update the dns masq file
  def write_dnsmasq_conf
    dm_file = []

    dhcp_server_settings = DhcpServerSettings.find( :first )
    dns_server_settings = DnsServerSettings.find( :first )

    dm_file << <<EOF
## #{Time.new}
## Auto Generated by the Untangle Net Alpaca
## If you modify this file manually, your changes
## may be overriden
EOF
       
    dm_file << dhcp_config( dhcp_server_settings, dns_server_settings )
    dm_file << dns_config( dhcp_server_settings, dns_server_settings )

    os["override_manager"].write_file( DnsMasqConfFile, dm_file.join( "\n" ), "\n" )
  end

  def dns_config( dhcp_server_settings, dns_server_settings )
    if dns_server_settings.nil?
      logger.warn( "no dns settings, not writing the file" );
      return ""
    end
    
    unless dns_server_settings.enabled
      logger.debug( "DNS Settings are disabled, not writing the file" );
      return ""
    end

    settings = []
    
    ## localize queries
    settings << FlagDnsLocalize

    ## Expand hosts so that unqualified hostnames lookup on local entries
    settings << FlagDnsExpandHosts

    settings << "#{FlagDnsHostFile}=#{DnsMasqHostFile}"

    ## append the dns servers to use
    settings << dhcp_name_servers

    ## set the domain name suffix
    settings << "#{FlagDnsLocalDomain}=#{domain_name_suffix}"
    settings.join( "\n" )
  end

  def dhcp_name_servers
    name_servers = []
    conditions = [ "wan=? and config_type=?", true, InterfaceHelper::ConfigType::STATIC ]
    i = Interface.find( :first, :conditions => conditions )

    unless i.nil?
      config = i.current_config

      next if config.nil?
      name_servers << config.dns_1
      name_servers << config.dns_2
    end

    ## Delete all of the empty name servers, and fix the lines.
    name_servers = name_servers.delete_if { |ns| ns.nil? || ns.empty? }
    name_servers.map { |ns| "#{FlagDnsServer}=#{ns}" }.join( "\n" )
  end

  def dhcp_config( dhcp_server_settings, dns_server_settings )
    if dhcp_server_settings.nil?
      logger.warn( "no dhcp settings, not writing the file" );
      return ""
    end
    
    unless dhcp_server_settings.enabled
      logger.debug( "DHCP Settings are disabled, not writing the file" );
      return ""
    end

    if ( IPAddr.parse( dhcp_server_settings.start_address ).nil? || 
         IPAddr.parse( dhcp_server_settings.end_address ).nil? )
      logger.warn( "Invallid start or end address" );
      return ""
    end
    
    duration = dhcp_server_settings.lease_duration
    duration = DefaultDuration if duration <= 0
    duration = MinLeaseDuration if duration < MinLeaseDuration
    duration = MaxLeaseDuration if duration > MaxLeaseDuration

    settings = []
    
    ## Setup the range
    settings << "#{FlagRange}=#{dhcp_server_settings.start_address},#{dhcp_server_settings.end_address},#{duration}"
    
    gateway = calculate_gateway( dhcp_server_settings )
    netmask = calculate_netmask( dhcp_server_settings )
    
    ## Default gateway
    settings << "#{FlagOption}=#{OptionGateway},#{gateway}" unless gateway.nil?
    settings << "#{FlagOption}=#{OptionNetmask},#{netmask}" unless netmask.nil?

    ## Static entries
    DhcpStaticEntry.find( :all ).each do |dse| 
      settings << "#{FlagDhcpHost}=#{dse.mac_address},#{dse.ip_address},24h"
    end

    return settings.join( "\n" )
  end

  def domain_name_suffix
    settings = DnsServerSettings.find(:first)
    return DefaultDomain if ( settings.nil? )
    
    ## Set the domain name
    domain = settings.suffix

    ## REVIEW: shoud validate that domain is a valid value
    return DefaultDomain if ( domain.nil? || domain.empty? )
    return domain
  end
  
  def calculate_gateway( dhcp_server_settings )
    gateway = dhcp_server_settings.gateway
    gateway.strip! unless gateway.nil?

    return gateway if valid?( gateway )

    ## validate the start range.
    return nil if IPAddr.parse( dhcp_server_settings.start_address ).nil?

    ## Find the first interface that is in this range.
    ## Find the interface this is being routed out of.
    
    ## sample line:
    ## 1.2.3.4 via 192.168.77.2 dev eth0  src 192.168.77.128  # if there is a next hop
    ## 192.168.77.2 dev eth0 src 192.168.77.128 # if there isn't a next hop
    route = `ip route get #{dhcp_server_settings.start_address}`.split( "\n" )[0]

    ## Nothing to do if the route isn't found
    return nil if route.nil?
    route = route.split( " " )

    ## REVIEW : not sure if if the language is not english then via will not be used.
    ## If the next hop is local, then 
    
    if (( route.size == 7 ) && ( route[1] == "via" ))
      os_name = route[4]
    else
      os_name = route[2]
    end

    next_hop = `ip route show | awk '/default via.*#{os_name}/ { print $3 }'`.strip

    ## Default gateway is not on the same interface.
    return nil if next_hop.empty?
    
    return next_hop.strip
  end

  def calculate_netmask( dhcp_server_settings )
    netmask =dhcp_server_settings.netmask
    netmask.strip! unless netmask.nil?

    ## should check if this is a valid netmask
    return netmask if valid?( netmask )

    return nil
  end

  def valid?( value )
    value.strip! unless value.nil?
    ## REVIEW strange constant.
    return false if ( value.nil? || value.empty? || IPAddr.parse( value ).nil? || ( value == "auto" ))
    return true
  end
end

