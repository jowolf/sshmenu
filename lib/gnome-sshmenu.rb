require 'sshmenu'
#require 'gconf2'

##############################################################################
# = License
#
# Copyright 2002-2009 Grant McLean <grant@mclean.net.nz>
#
# This package is free software; you can redistribute it and/or modify it
# under the terms of the License.txt file (a BSD-style license) distributed
# with the software:
#
# http://sshmenu.git.sourceforge.net/git/gitweb.cgi?p=sshmenu;a=blob;f=License.txt;hb=HEAD
#
# = Description
#
# Classes in the GnomeSSHMenu module inherit from classes in the SSHMenu module
# and override methods to provide GNOME-specific functionality.  The main
# differences are:
# * the use of gnome-terminal rather than xterm
# * support for gnome-terminal profiles
# * support for opening multiple host connections as tabs within a single
#   terminal window.

module GnomeSSHMenu

  # The GnomeSSHMenu::Factory class overrides the SSHMenu::Factory class to
  # provide alternate class mappings.

  class Factory <SSHMenu::Factory

    # Sets the default mapping for 'app.model' to GnomeSSHMenu::Config.

    def Factory.option_defaults
      return super.merge(
        :model_class    => GnomeSSHMenu::Config
      )
    end

    # Sets the default mapping for 'app' to GnomeSSHMenu::App.

    def Factory.inject_defaults
      mapper.inject('app' => GnomeSSHMenu::App)
      super
    end

  end

  ############################################################################
  # The GnomeSSHMenu::App class builds on SSHMenu::App to add support for
  # gnome-terminal and tabbed windows.

  class App <SSHMenu::App

    # Sets default class mappings to refer to GnomeSSHMenu dialog classes.

    def inject_defaults
      mapper.inject(
        'app.dialog.prefs' => GnomeSSHMenu::PrefsDialog,
        'app.dialog.host'  => GnomeSSHMenu::HostDialog,
        'app.dialog.menu'  => GnomeSSHMenu::MenuDialog
      )
      super
    end

    # Given a GnomeSSHMenu::HostItem, constructs a command line to open a
    # gnome-terminal window containing an SSH connection to the host.

    def build_window_command(host)
      command = 'gnome-terminal'
      if host.env_settings and host.env_settings.length > 0
        command = host.env_settings + command + ' --disable-factory'
      end
      if host.geometry and host.geometry.length > 0
        command += " --geometry=#{host.geometry}"
      end
      if host.profile and host.profile.length > 0
        command += ' --window-with-profile=' + shell_quote(host.profile)
      end
      command += ' --title=' + shell_quote(host.title)
      ssh_cmnd = "#{ssh_command(host)} #{host.sshparams_noenv}"
      command += ' -e ' + shell_quote("sh -c #{shell_quote(ssh_cmnd)}")
      return command + ' &';
    end

    # Called when the user selects 'Open all as tabs' from a sub menu.  Calls
    # build_tabbed_window_command to open a multi-tabbed terminal window.

    def open_tabs(menu)
      return unless menu.items.length > 0
      add_key
      system(build_tabbed_window_command(menu))
    end

    # Given a GnomeSSHMenu::MenuItem, constructs a command line to open a
    # gnome-terminal window containing multiple tabs - each with an SSH
    # connection to a host.

    def build_tabbed_window_command(menu)
      command = 'gnome-terminal'
      first_host = true
      menu.items.each do |i|
        if i.host?
          if first_host
            if i.env_settings and i.env_settings.length > 0
              command = i.env_settings + command + ' --disable-factory'
            end
            if i.geometry and i.geometry.length > 0
              command += " --geometry=#{i.geometry}"
            end
          end
          if i.profile and i.profile.length > 0
            command += ' --tab-with-profile=' + shell_quote(i.profile)
          else
            command += " --tab-with-profile=Default"
          end
          command += ' --title=' + shell_quote(i.title)
          ssh_cmnd = "#{ssh_command(i)} #{i.sshparams_noenv}"
          command += ' -e ' + shell_quote("sh -c #{shell_quote(ssh_cmnd)}")
          first_host = false
        end
      end
      return command + ' &'
    end

    # Helper routine for SSHMenu::App#show_hosts_menu.  Adds the 'Open all as
    # tabs' menu item if the option is enabled.

    def menu_add_menu_options(mif, parents, item)
      return unless item.has_children?
      need_sep = super(mif, parents, item)
      if @config.menus_open_tabs?
        mif.create_item(
          item_path(parents, item) + '/Open all as tabs', "<Item>"
        ) { open_tabs(item) }
        need_sep = true
      end
      return need_sep
    end

    # Debian's 'popcon' (Popularity Contest) normally reports the sshmenu-gnome
    # package as 'installed but not used' since the panel applet does not
    # access /usr/bin/sshmenu-gnome.  This routine updates the atime on that
    # file each time the applet starts.  This functionality is completely
    # non-essential and can be safely disabled in the unlikely event that it
    # causes some problem.

    def appease_popcon # :nodoc:
      # update access time on a file the Debian popcon is looking at :-)
      begin
        open('/usr/bin/sshmenu-gnome') { |f| f.readline }
      rescue Exception
      end
      super
    end

  end

  ############################################################################
  # The GnomeSSHMenu::Config class builds on SSHMenu::Config to add support for
  # gnome-terminal with configurable profiles and tabbed windows.

  class Config <SSHMenu::Config

    # GConf key for retrieving a list of terminal profiles.
    GnomeTermProfiles = '/apps/gnome-terminal/global/profile_list'

    # GConf key template to get visible name for a profile.
    GnomeTermProfName = '/apps/gnome-terminal/profiles/%s/visible_name'

    # Sets default class mappings to refer to GnomeSSHMenu item classes.

    def inject_defaults
      mapper.inject(
        'app.model.item'     => GnomeSSHMenu::Item,
        'app.model.hostitem' => GnomeSSHMenu::HostItem,
        'app.model.menuitem' => GnomeSSHMenu::MenuItem
      )
      super
    end

    # Retrieves a list of gnome-terminal profile names from the GConf registry.

    def list_profiles
      profiles = []
      client = GConf::Client.default
      names = client[GnomeTermProfiles] or return profiles
      names.each { |prof_name|
        title = client[sprintf(GnomeTermProfName, prof_name)]
        profiles.push(title) unless title.nil?
      }
      profiles.sort! { |a,b| a.upcase <=> b.upcase }
      return profiles
    end

    # Returns true if the 'Open all as tabs' global option is enabled.

    def menus_open_tabs?
      if opt = get('menus_open_tabs')
        return opt != 0
      end
      return false
    end

    # Used to set the 'Open all as tabs' global option.
    def menus_open_tabs=(val)
      set('menus_open_tabs', val ? 1 : 0)
    end

  end

  ############################################################################
  # The GnomeSSHMenu::PrefsDialog class builds on SSHMenu::PrefsDialog to add
  # support for tabbed gnome-terminal windows.

  class PrefsDialog <SSHMenu::PrefsDialog

    # Stores the value of the 'Open all as tabs' checkbox and then delegates to
    # SSHMenu::PrefsDialog#save_options.

    def save_options
      @config.menus_open_tabs = @chk_open_tabs.active?
      super
    end

    # Adds the 'Open all as tabs' checkbox to the global option pane created by
    # SSHMenu::PrefsDialog#make_options_pane.

    def make_options_pane
      table = super
      r = table.get_property('n-rows')

      @chk_open_tabs = Gtk::CheckButton.new(
        'include "Open all as _tabs" selection', true
      )
      @chk_open_tabs.active = @config.menus_open_tabs?
      table.attach(
        @chk_open_tabs, 0, 1, r, r+1, Gtk::EXPAND|Gtk::FILL, Gtk::FILL, 0, 0
      )

      return table
    end

  end

  ############################################################################
  # The GnomeSSHMenu::HostDialog class builds on SSHMenu::HostDialog to add
  # support for gnome-terminal profiles.

  class HostDialog <SSHMenu::HostDialog

    # Adds a drop-down menu for selecting a terminal profile and then delegates
    # to SSHMenu::HostDialog#add_other_inputs.

    def add_other_inputs
      @profiles = @config.list_profiles

      prof_menu = Gtk::ComboBox.new(true)
      prof_menu.append_text('< None >')
      prof_menu.active = 0
      @profiles.each_index { |i|
        prof_menu.append_text(@profiles[i])
        prof_menu.active = i + 1 if @profiles[i] == @host.profile
      }

      @profile_menu = add_input('Profile', @host.profile, prof_menu)
      super()
    end

    # Helper routine for dialog_to_host.  Returns the name of the profile
    # currently selected in the drop-down menu.

    def selected_profile
      i = @profile_menu.active
      if i > 0
        return @profiles[i-1]
      else
        return ''
      end
    end

    # Delegates to SSHMenu::HostDialog#dialog_to_host and adds suport for
    # saving the profile name.

    def dialog_to_host(host=nil)
      host = super(host)
      host.profile = selected_profile
      return host
    end

  end

  ############################################################################
  # An empty class the inherits from SSHMenu::MenuDialog

  class MenuDialog <SSHMenu::MenuDialog

  end

  ############################################################################
  # An empty class the inherits from SSHMenu::Item

  class Item <SSHMenu::Item

  end

  ############################################################################
  # Inherits from SSHMenu::HostItem and adds support for storing the selected
  # gnome-terminal profile name.

  class HostItem <SSHMenu::HostItem

    # Adds the gnome-terminal profile name to the list of attributes supported
    # by SSHMenu::HostItem.

    def HostItem.attributes
      super + [ :profile ]
    end

    make_accessors

  end

  ############################################################################
  # An empty class the inherits from SSHMenu::MenuItem

  class MenuItem <SSHMenu::MenuItem

  end

end
