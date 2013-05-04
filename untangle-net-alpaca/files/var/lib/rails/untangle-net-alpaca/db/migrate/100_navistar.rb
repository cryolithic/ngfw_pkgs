
class Navistar < Alpaca::Migration
  def self.up
    drop_table :arp_eater_networks
    drop_table :arp_eater_settings

    remove_column :uvm_settings, :interface_order
  end
  
  def self.down
    # original creation format (040)
    create_table :arp_eater_settings do |table|
      table.column :enabled, :boolean, :default => false
      table.column :gateway, :string
      table.column :timeout_ms, :integer
      table.column :rate_ms, :integer
      table.column :broadcast, :boolean
      table.column :interface, :string
    end
    create_table :arp_eater_networks do |table|
      table.column :enabled, :boolean, :default => false
      table.column :description, :string
      table.column :spoof, :boolean
      table.column :passive, :boolean, :default => true
      table.column :ip, :string
      table.column :netmask, :string
      table.column :gateway, :string
      table.column :timeout_ms, :integer
      table.column :rate_ms, :integer
    end

    # later updates (080)
    add_column :arp_eater_networks, :is_spoof_host_enabled, :boolean, :default => true
    add_column :arp_eater_settings, :nat_hosts, :string, :default => ""

    # re-add column
    add_column :uvm_settings, :interface_order, :string, :default => UvmHelper::DefaultOrder
  end
end