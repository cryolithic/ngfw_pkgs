## REVIEW This should be renamed to dhcp_server_controller.
## REVIEW Should create a consistent way to build these tables.
#
# $HeadURL$
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
class DhcpController < ApplicationController
  def get_settings
    warnings = []
    settings = { "warnings" => warnings }

    dhcp_server_settings = DhcpServerSettings.find( :first )
    dhcp_server_settings = DhcpServerSettings.new if dhcp_server_settings.nil?

    if dhcp_server_settings.enabled == true and \
        ( dhcp_server_settings.start_address.nil? \
          or dhcp_server_settings.end_address.nil? \
          or dhcp_server_settings.start_address.length == 0 \
          or dhcp_server_settings.end_address.length == 0 )
      warnings << "DHCP::StartAndEndRequired"
    elsif ! Interface.valid_dhcp_server?
      warnings << "DHCP::IncorrectSubnet"
    end

    settings["dhcp_server_settings"] = dhcp_server_settings

    settings["dhcp_static_entries"] = DhcpStaticEntry.find( :all )

    settings["dhcp_dynamic_entries"] = os["dhcp_server_manager"].dynamic_entries

    json_result( :values => settings )
  end
  
  def set_settings
    s = json_params
    
    ## Check for duplicate MAC Addresses
    mac_addresses = {}
    ip_addresses = {}
    static_entries = s["dhcp_static_entries"]
    unless static_entries.nil?
      static_entries.each do |se|
        ma, ip = se["mac_address"], se["ip_address"]
        return json_error( "Duplicate MAC Address '%s'" % (ma)) unless mac_addresses[ma].nil?
        return json_error( "Duplicate IP Address '%s'" % (ip)) unless ip_addresses[ip].nil?
        mac_addresses[ma] = 0
        ip_addresses[ip] = 0
      end

      DhcpStaticEntry.destroy_all
      static_entries.each { |entry| DhcpStaticEntry.new( entry ).save }
    end
    
    dhcp_server_settings = DhcpServerSettings.find( :first )
    dhcp_server_settings = DhcpServerSettings.new if dhcp_server_settings.nil?
    dhcp_server_settings.update_attributes( s["dhcp_server_settings"] )
    dhcp_server_settings.save

    os["dhcp_server_manager"].commit
    
    json_result
  end

  def get_leases
    json_result( :values =>os["dhcp_server_manager"].dynamic_entries )
  end
  
  alias_method :index, :extjs

  alias_method :secret_field, :extjs

  def create_static_entry
    @static_entry = DhcpStaticEntry.new
    if ! params[:mac_address].nil? && ! params[:ip_address].nil?
      @static_entry.mac_address = params[:mac_address]
      @static_entry.ip_address = params[:ip_address]
      @static_entry.description = params[:description]
    end
  end

  def manage
    @dhcp_server_settings = DhcpServerSettings.find( :first )
    @dhcp_server_settings = DhcpServerSettings.new if @dhcp_server_settings.nil?
    manage_entries
    if @dhcp_server_settings.enabled == true and \
        ( @dhcp_server_settings.start_address.nil? \
          or @dhcp_server_settings.end_address.nil? \
          or @dhcp_server_settings.start_address.length == 0 \
          or @dhcp_server_settings.end_address.length == 0 )
      flash[:warning] = "Start and End is required if DHCP Server is enabled.".t
    elsif ! Interface.valid_dhcp_server?
      flash[:warning] = "DHCP Server is configured on a subnet that is not on any configured interfaces.".t
    end
  end

  def manage_entries
    @dhcp_server_settings = DhcpServerSettings.find( :first )
    @dhcp_server_settings = DhcpServerSettings.new if @dhcp_server_settings.nil?
    @static_entries = DhcpStaticEntry.find( :all )

    @static_entries = @static_entries.sort_by { |a| IPAddr.parse(a.ip_address).to_i }
    ## Retrieve all of the dynamic entries from the DHCP server manager
    refresh_dynamic_entries
  end

  def static_entries_json
    static_entries = DhcpStaticEntry.find( :all )
    json = ApplicationHelper.active_record_to_json( static_entries )
    render :json => json
  end
  
  def dynamic_entries_json
    dynamic_entries = os["dhcp_server_manager"].dynamic_entries
    json = ApplicationHelper.active_record_to_json( dynamic_entries )
    render :json => json
  end

  def save
    ## Review : Internationalization
    return redirect_to( :action => "manage" ) if ( params[:commit] != "Save".t )

    dhcp_server_settings = DhcpServerSettings.find( :first )
    dhcp_server_settings = DhcpServerSettings.new if dhcp_server_settings.nil?
    dhcp_server_settings.update_attributes( params[:dhcp_server_settings] )
    dhcp_server_settings.save
    
    save_entries

    os["dhcp_server_manager"].commit

    ## Review : should have some indication that is saved.
    return redirect_to( :action => "manage" )
  end

  def custom_field
    @dhcp_server_settings = DhcpServerSettings.find( :first )
    
    if @dhcp_server_settings.nil?
      flash[:warning] = "Save DHCP settings before configuring custom field."

      ## Review : should have some indication that is saved.
      return redirect_to( :action => "manage" )
    end
  end

  def save_custom_field
    dhcp_server_settings = DhcpServerSettings.find( :first )
    
    if dhcp_server_settings.nil?
      flash[:warning] = "Save DHCP settings before configuring custom field."

      ## Review : should have some indication that is saved.
      return redirect_to( :action => "manage" )
    end

    dhcp_server_settings.update_attributes( params[:dhcp_server_settings] )
    dhcp_server_settings.save

    os["dhcp_server_manager"].commit

    return redirect_to( :action => "custom_field" )
  end

  def save_entries
    static_entry_list = []
    indices = params[:static_entries]
    mac_addresses = params[:mac_address]
    ip_addresses = params[:ip_address]
    descriptions = params[:description]

    seen_mac_addresses = []
    seen_ip_addresses = []

    errors = ""

    position = 0
    unless indices.nil?
      indices.each do |key|
	if seen_mac_addresses.include?( mac_addresses[key] )
          errors = errors + " Ignoring duplicate MAC address " + mac_addresses[key] + ". "
          next
	end

	if seen_ip_addresses.include?( ip_addresses[key] )
          errors = errors + " Ignoring duplicate IP address " + ip_addresses[key] + ". "
	  next
        end

        dse = DhcpStaticEntry.new
        dse.mac_address, dse.ip_address, dse.description = mac_addresses[key], ip_addresses[key], descriptions[key]
        dse.position, position = position, position + 1
        static_entry_list << dse

        seen_mac_addresses << mac_addresses[key]
        seen_ip_addresses << ip_addresses[key]
      end
    end

    if errors.length > 0
	if ! flash.has_key?( :error )
            flash[:error] = ""
        end

        flash[:error] = flash[:error] + errors
    end

    DhcpStaticEntry.destroy_all
    static_entry_list.each { |dse| dse.save }

    os["dhcp_server_manager"].commit
    #return redirect_to( :action => "manage_entries" )
  end

  def refresh_dynamic_entries
    ## Retrieve all of the dynamic entries from the DHCP server manager
    @dynamic_entries = os["dhcp_server_manager"].dynamic_entries 
    @dynamic_entries = @dynamic_entries.sort_by { |a| IPAddr.new(a.ip_address).to_i }   
  end
end
