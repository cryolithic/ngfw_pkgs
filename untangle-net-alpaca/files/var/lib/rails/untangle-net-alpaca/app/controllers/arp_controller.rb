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
class ArpController < ApplicationController
  def get_settings
    settings = {}
    settings["active_arps"] = StaticArp.get_active( os )
    settings["static_arps"] = StaticArp.find( :all )
    json_result( :values => settings )
  end

  def get_active
    json_result( :values => StaticArp.get_active( os ))
  end
  
  def set_settings
    s = json_params

    StaticArp.destroy_all

    static_arps = s["static_arps"]
    
    unless static_arps.nil?
      static_arps.each { |entry| StaticArp.new( entry ).save }
    end

    os["arps_manager"].commit

    json_result
  end

  alias_method :index, :extjs

  def manage
    @active_arps = StaticArp.get_active( os )
    @active_arps = @active_arps.sort_by do |a| 
      address = IPAddr.parse(a.ip_address)
      next 0 if address.nil?
      address.to_i
    end

    @active_arps = @active_arps.sort_by { |a| a.interface }
    @static_arps = StaticArp.find( :all )
    @static_arps = [StaticArp.new] if @static_arps.nil?
  end

  def save
    ## Review : Internationalization
    return redirect_to( :action => "manage" ) if ( params[:commit] != "Save".t )

    StaticArp.destroy_all
    
    if ! params[:static_arp].nil?
      params[:static_arp].each do |static_arp_row| 
        if (!(params[:hw_addr][static_arp_row].nil?) \
            && params[:hw_addr][static_arp_row].length > 0\
            && !(params[:hostname][static_arp_row].nil?)\
            && params[:hostname][static_arp_row].length > 0)
          
          static_arp_obj = StaticArp.new
          static_arp_obj.update_attributes( :hw_addr => params[:hw_addr][static_arp_row], :hostname => params[:hostname][static_arp_row] )
          static_arp_obj.save
        end
      end
    end
    
    os["arps_manager"].commit

    ## Review : should have some indication that is saved.
    return redirect_to( :action => "manage" )
  end
  def create_arp
    @static_arp = StaticArp.new
  end
end
