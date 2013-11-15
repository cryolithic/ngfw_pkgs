#
# $HeadURL: svn://chef/work/pkgs/untangle-net-alpaca/files/var/lib/rails/untangle-net-alpaca/vendor/plugins/alpaca/lib/alpaca/localization_extensions.rb $
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

module Alpaca::ValidatorExtensions
  ## Shortcut, to allow controlle and active records to just call validtor.is_hostname?( "foo" )
  def validator
    ::Alpaca::Validator
  end
end

ActionController::Base.send :include, Alpaca::ValidatorExtensions

Alpaca::OS::ManagerBase.send :include, Alpaca::ValidatorExtensions

Alpaca::Component.send :include, Alpaca::ValidatorExtensions