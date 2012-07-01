require 'getoptlong'
require 'pathname'
require 'ftools'
require 'singleton'
require 'gtk2'
require 'yaml'
require 'socket'
require 'base64'

if(Gtk::BINDING_VERSION[0] * 100 + Gtk::BINDING_VERSION[1] < 15)
  Gtk.init   # only required for ruby-gnome2 bindings less than 0.15
end

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
# SSHMenu is a simple GUI app that provides a menu for initiating SSH
# connections.  Select a host from the menu and up pops a new terminal window
# containing an SSH session to the selected host.
#
# Classes in the SSHMenu module namespace implement the basic application using
# Gtk with no GNOME dependencies.  The GnomeSSHMenu module contains classes
# which inherit from these classes and add GNOME-specific functionality.
#
# The main class in this module is SSHMenu::App which is instantiated using
# SSHMenu::Factory.
#

module SSHMenu

  @@VERSION      = '3.18'
  @@HOMEPAGE_URL = 'http://sshmenu.sourceforge.net/'

  # Returns the version number of this release of SSHMenu

  def SSHMenu.version
    return @@VERSION
  end

  # Returns the URL of the SSHMenu project home page (for display in the
  # 'About' box)

  def SSHMenu.homepage_url
    return @@HOMEPAGE_URL
  end

  class ShowVersionException < RuntimeError
  end

  # The ClassMapper is a singleton object shared by all classes throughout the
  # application.  Its job is to map a symbolic name such as 'app.dialog.host'
  # to a class name such as SSHMenu::HostDialog.
  #
  # It is possible to customise the behaviour of the application by 'injecting'
  # mappings which cause different parts of the application to be built using
  # custom classes.
  #
  # It is not generally possible to modify a mapping after it has been injected
  # since objects of the original class may already have been constructed.  The
  # reset_mappings method can be used to discard all known mappings, but this
  # is really only useful to the regression test suite.

  class ClassMapper

    include Singleton

    def initialize # :nodoc:
      reset_mappings
    end

    # Discard all known mappings.  Used by the regression tests to create a
    # series of applications with test classes injected at different points.

    def reset_mappings
      @class_map = { }
    end

    # Takes a symbolic path name such as 'app.dialog.host' and returns a class
    # object such as SSHMenu::HostDialog.  Throws a RuntimeError if the
    # requested path is not mapped to a class.

    def get_class(path)
      return @class_map[path] if @class_map[path]
      raise RuntimeError, "Could not find class for path '#{path}' in:\n" + self
    end

    # Returns a dump of all mappings as a multi-line string - primarily for
    # debugging.

    def to_str
      @class_map.keys.sort.map { |k| sprintf("%-20s %s\n", k, @class_map[k]) }.join("")
    end

    # Used to define new mappings.  Takes a hash of pathname => classname pairs.

    def inject(map)
      map.keys.each { |k| @class_map[k] = map[k] unless @class_map.key?(k) }
    end
  end

  # Methods in this class are called from a wrapper script to create an
  # application object.  The wrapper script will typically follow this
  # sequence:
  #
  # * create some sort of top-level application window (a Gtk object)
  # * optionally call SSHMenu::Factory.inject_defaults to override default
  #   class mappings
  # * call SSHMenu::Factory.make_app
  # * call Gtk.main to enter the main event loop

  class Factory

    # Used to create an application object.  The object will be of the class
    # associated with the path 'app' in the ClassMapper (default:
    # SSHMenu::App).
    #
    # This method accepts a hash of options - all of which may be omitted.
    # The following options are recognised:
    #
    # * <tt>:window</tt> - a Gtk::Window into which the application UI
    #   (essentially a single button) will be packed
    #
    # * <tt>:model_class</tt> - the class which should be used to handle reading
    #   and writing the config file (default is SSHMenu::Config)
    #
    # * <tt>:args</tt> - command-line arguments passed to the wrapper script
    #   (ARGV will be used by default)
    #
    # The wrapper script can optionally supply a block to this method.  When
    # the user selects a host from the menu, the block will be invoked instead
    # of the default launch method and will be passed the host object.
    #
    # Any exceptions generated during construction of the application will be
    # trapped.  If possible, the error details will be displayed in a popup
    # window since the STDERR of a panel applet is not typically visible to a
    # user.
    #
    # :call-seq:
    #   Factory.make_app(options) { optional block } -> SSHMenu::App
    #

    def Factory.make_app(*args, &launch_proc)
      begin
        options = parse_options(args)
        mapper.inject('app.model' => options[:model_class])
        config_file = extract_config_file(options[:args])
        config = mapper.get_class('app.model').new(:filename => config_file)

        inject_defaults
        return mapper.get_class('app').new(config, options, launch_proc)
      rescue SystemExit
        exit
      rescue ShowVersionException
        puts "SSHMenu Version #{SSHMenu.version}"
        exit
      rescue Exception => detail
        mapper.inject('app' => SSHMenu::App)
        mapper.get_class('app').fatal_error(detail)
        exit
      end
    end

    # Helper routine called by Factory.make_app to validate the supplied options
    # and apply defaults.

    def Factory.parse_options(args)
      default = option_defaults
      if args[0].is_a?(Hash)
        args = args[0]
      else
        args = { :window => args[0], :model_class => args[1] }
      end
      options = {}
      args.each do |k,v|
        raise "Unrecognised option '#{k}'" unless default.has_key?(k)
        options[k] = v
      end
      default.each do |k,v|
        options[k] = v if options[k].nil?
      end
      return options
    end

    # Sets allowable options and default values for options passed to make_app.
    # and apply defaults.

    def Factory.option_defaults
      return {
        :window         => nil,
        :model_class    => SSHMenu::Config,
        :args           => ARGV
      }
    end

    # Scans through the supplied command-line arguments and extracts the
    # config file name if supplied.  This is done early because the 'app'
    # class is responsible for handling command line arguments but the config
    # file might contain a class mapping for 'app'.

    def Factory.extract_config_file(args = [])
      i = args.index('--config-file') || args.index('-c') || return
      return args[i+1]
    end

    # Returns the ClassMapper singleton object

    def Factory.mapper
      ClassMapper.instance
    end

    # A proxy for SSHMenu::ClassMapper.inject

    def Factory.inject_defaults
        mapper.inject('app' => SSHMenu::App)
    end

  end

  ############################################################################
  # The SSHMenu::App class implements the framework of the application - a
  # simple menu.  Each item on the menu represents an SSH connection to a host,
  # to be opened in a new terminal window.
  #
  # This class is responsible for rendering the menu and taking appropriate
  # action when the user makes a selection from the menu.
  #
  # The application class uses the ClassMapper to delegate chunks of
  # functionality to different classes as follows:
  #
  # ['app.model'        => SSHMenu::Config]      manage the data model - reading
  #                                              and writing the config file
  #                                              and maintaining an in-memory
  #                                              representation
  # ['app.history'      => SSHMenu::History]     manage quick-connect command
  #                                              history
  # ['app.dialog.prefs' => SSHMenu::PrefsDialog] manage the preferences dialog
  # ['app.dialog.host'  => SSHMenu::HostDialog]  manage the dialog for editing
  #                                              a host
  # ['app.dialog.menu'  => SSHMenu::MenuDialog]  manage the dialog for editing
  #                                              a sub-menu
  # ['app.geograbber'   => SSHMenu::GeoGrabber]  manage 'grabbing' the geometry
  #                                              of a running window
  #

  class App

    @@display = nil
    AskpassPaths = [
      '/usr/bin/ssh-askpass',
      '/etc/alternatives/ssh-askpass',
      '/usr/lib/ssh/gnome-ssh-askpass',
      '/usr/lib/ssh/x11-ssh-askpass',
    ]

    # The 'app.model' object
    attr_reader  :config
    # The X11 DISPLAY object
    attr_reader  :display

    # Called by SSHMenu::Factory#make_app

    def initialize(config, options, launch_proc)
      @config      = config
      @options     = options
      @launch_proc = launch_proc
      @have_bcvi   = false
      @socket_window_id = nil
      @debug_level = 0
      @context_menu_active = false
      @deferred_actions    = []

      getopts(@options[:args])
      @app_win     = @options[:window] || default_container
      @entry_box   = nil

      inject_defaults
      get_initial_config
      check_for_bcvi
      @history   = mapper.get_class('app.history').new(config)

      @have_key  = false
      @is_applet = @app_win.respond_to?('popup_component')

      if not @deferred_actions.empty?
        @deferred_actions.each { |a| a.call() }
      end

      build_ui() unless @app_win == :none
    end

    # Returns true if the application window is a panel applet or false if
    # it's a normal application window

    def is_applet?
      return @is_applet
    end

    # This method returns a boolean value which controls whether or not the
    # preferences dialog includes an option to display a text entry box.  If
    # the application is running in a panel applet, version 0.19 of the Ruby
    # bindings is required to display a text entry.  For non-applet contexts,
    # the return value is always true.

    def can_show_entry?
      if @is_applet
        return GLib.check_binding_version?(0, 19, 0)
      end
      return true
    end

    # Called if no container window was supplied to the constructor.  Most
    # commonly, the method would create and return a new top-level window
    # object.  However if the --socket-window-id option was supplied, a
    # Gtk::Plug object will be created instead.  This allows another
    # application to embed the SSHMenu user interface.

    def default_container()
      window = nil
      if @socket_window_id
        window       = Gtk::Plug.new(@socket_window_id)
      else
        window       = Gtk::Window.new( Gtk::Window::TOPLEVEL )
        window.title = 'SSH Menu'
      end
      window.signal_connect('destroy') { Gtk.main_quit }
      return window
    end

    # Called from the constructor to handle building the main user interface
    # (a button).

    def build_ui()
      hbox = Gtk::HBox.new(false, 0)
      @app_win.add(hbox)

      evbox = Gtk::EventBox.new
      evbox.signal_connect('button-press-event') { |w,e| on_click(w,e) }
      hbox.pack_start(evbox, false, false)

      @frame = Gtk::Frame.new
      set_button_border;
      evbox.add(@frame)

      label = Gtk::Label.new("SSH")
      label.set_padding(2, 2)
      @frame.add(label)

      tooltips = Gtk::Tooltips.new
      tooltips.set_tip(evbox, @config.tooltip_text, nil);

      @app_win.show_all

      @entry_box = build_text_entry
      hbox.pack_start(@entry_box, true, true) unless @entry_box.nil?
      show_hide_text_entry

      set_up_applet_menu

      # For multi-DISPLAY setups
      @@display = evbox.screen
      ENV['DISPLAY'] = @@display.display_name

      appease_popcon
    end

    # Build a text entry box with resize handle for display next to the main
    # button (if required)

    def build_text_entry
      hbox       = Gtk::HBox.new(false, 0)
      entry      = Gtk::Entry.new
      completion = Gtk::EntryCompletion.new
      store      = Gtk::ListStore.new(String)

      @completion_actions = []

      entry.width_chars           = 1
      entry.width_request         = @config.get('entry_width', 70)
      completion.model            = store
      completion.popup_completion = true
      completion.text_column      = 0
      completion.popup_set_width  = false

      completion.set_match_func { true }

      entry.completion = completion

      entry.signal_connect('activate') do
        @history.add_line(entry.text)
        open_win(@config.host_from_text(entry.text))
        entry.text = ''
      end

      completion.signal_connect('action-activated') do |c,i|
        target = @completion_actions[i]
        if target.is_a?(String)
          prefs = mapper.get_class('app.dialog.prefs').new(self, @config)
          prefs.append_host(@config.host_from_text(entry.text))
        else
          open_win(@completion_actions[i])
        end
        entry.text = ''
      end

      entry.signal_connect('button-press-event') do |w,e|
        if @app_win.respond_to?('request_focus')
          @app_win.request_focus(e.time)
        end
        false
      end

      entry.signal_connect('focus-in-event') do
        @history.freshen
        false
      end

      entry.signal_connect('changed') do
        update_entry_completions(store, entry.text)
        update_entry_actions(completion, entry.text)
      end

      hbox.pack_start(entry, true, true)      # Expand and fill

      handle = entry_resize_handle(entry)
      hbox.pack_start(handle, false, true)    # No expand but fill (y?)

      return hbox
    end

    # Add a resize handle to the right of the entry box

    def entry_resize_handle(entry)
      handle = Gtk::DrawingArea.new
      handle.set_size_request(3,10)
      handle.events = Gdk::Event::BUTTON_PRESS_MASK |
                      Gdk::Event::BUTTON_RELEASE_MASK |
                      Gdk::Event::POINTER_MOTION_MASK

      handle.signal_connect('realize') do
        handle.window.cursor = Gdk::Cursor.new(Gdk::Cursor::RIGHT_SIDE)
      end

      dragging = false
      x_start  = 0
      w_start  = 0
      handle.signal_connect('button-press-event') do |w,e|
        if e.button = 1
          dragging = true
          (x,y,w,h) = entry.window.geometry
          w_start = w
          x_start = e.x_root
        end
      end

      handle.signal_connect('button-release-event') do |w,e|
        if e.button = 1
          dragging = false
          @config.set('entry_width', entry.width_request)
          @config.save
        end
      end

      handle.signal_connect('motion-notify-event') do |w,e|
        if dragging
          w = w_start + e.x_root - x_start
          if w >= 20
            entry.width_request = w
            @app_win.resize(1,1) if @app_win.respond_to?('resize')
          end
        end
      end

      return handle
    end

    # Toggles the visibility of the text entry widget based on the value of the
    # 'show text entry' option (requires at least version 0.19 of the Ruby Gtk
    # bindings)

    def show_hide_text_entry
      return unless @entry_box
      if @config.show_entry?
        return unless can_show_entry?
        @entry_box.show_all if not @entry_box.visible?
      elsif @entry_box.visible?
        @entry_box.hide
        @app_win.resize(1,1) if @app_win.respond_to?('resize')
      end
    end

    # Adds the 'Properties' and 'About' options to the applet context
    # (right-click) menu - if the container is an applet.

    def set_up_applet_menu
      return unless @is_applet and @app_win.respond_to?('set_menu')
      xml = %Q{<popup name="button3">
                 <menuitem name="prefs" verb="prefs" _label="Preferences"
                   pixtype="stock" pixname="gtk-properties" />
                 <menuitem name="about" verb="about" _label="About"
                   pixtype="stock" pixname="gtk-about" />
               </popup>}

      verbs = [['prefs', Proc.new{edit_preferences}],
               ['about', Proc.new{applet_menu_about}]]

      @app_win.set_menu xml, verbs
      @context_menu_active = true
    end

    # Callback invoked when the 'About' option on the context menu is
    # selected.

    def applet_menu_about
      dialog = Gtk::Dialog.new(
        nil,
        nil,
        Gtk::Dialog::DESTROY_WITH_PARENT,
        [ Gtk::Stock::CLOSE, Gtk::Dialog::RESPONSE_NONE ]
      )
      dialog.has_separator = false
      dialog.title = 'About SSHMenu'
      about_pane = make_about_pane
      dialog.vbox.add(about_pane)
      dialog.screen = @@display if @@display
      dialog.show_all
      dialog.run
      dialog.destroy
    end

    # Constructs the contents of the 'About' box, including: program name and
    # version, copyright information and a link to the project home page.

    def make_about_pane
      pane = Gtk::VBox.new(false, 12)
      panel = Gtk::VBox.new(false, 12)

      title = Gtk::Label.new
      title.set_markup("<span font_desc='sans bold 36'>SSHMenu</span>");
      title.selectable = true
      panel.pack_start(title, false, false, 0)

      version = Gtk::Label.new
      version.set_markup("<span font_desc='sans 24'>Version: #{SSHMenu.version}</span>");
      version.selectable = true
      panel.pack_start(version, false, false, 0)

      author = Gtk::Label.new
      detail = '(c) 2005-2009 Grant McLean &lt;grant@mclean.net.nz&gt;'
      author.set_markup("  <span font_desc='sans 10'>#{detail}</span>  ");
      author.selectable = true
      panel.pack_start(author, false, false, 10)

      evbox = Gtk::EventBox.new
      evbox.signal_connect('button-press-event') { |w,e| open_homepage() }
      evbox.signal_connect('realize') { |w| w.window.cursor = Gdk::Cursor.new(Gdk::Cursor::HAND2) }
      site_link = Gtk::Label.new
      site_link.set_markup("<span font_desc='sans 10' foreground='#0000FF' " +
                        "underline='single'>#{SSHMenu.homepage_url}</span>");
      evbox.add(site_link)
      panel.pack_start(evbox, false, false, 0)

      pane.pack_start(panel, true, false, 10)
      return pane
    end

    # Signal handler called to update the list of matching auto-completions
    # when text is typed into the entry box

    def update_entry_completions(store, text)
      store.clear
      return unless text.length > 0

      i = 0
      @history.each_match(text) do |line|
        store.set_value(store.append, 0, line)
        i += 1
        break if i > 10
      end
    end

    # Signal handler called to update the list of matching host connection
    # actions when text is typed into the entry box

    def update_entry_actions(completion, text)
      # Clear out current actions
      while not @completion_actions.empty? do
        completion.delete_action(0)
        @completion_actions.shift
      end
      return unless text.length > 0

      # Build a new list of actions
      match_start = []
      match_other = []
      pattern     = Regexp.quote(text)
      @config.each_item do |parents, item|
        next unless item.host?
        if item.title =~ /^#{pattern}/i
          match_start.push(item)
        elsif item.title =~ /#{pattern}/i
          match_other.push(item)
        end
      end

      @completion_actions = [match_start, match_other].flatten[0..9]
      @completion_actions.each_with_index do |item,i|
        completion.insert_action_markup(i, "<b>Host:</b> #{item.title}")
      end

      i = @completion_actions.length
      @completion_actions.push(text)
      completion.insert_action_markup(i, "<b>Add menu item:</b> #{text}")
    end

    # Show/hide the border around the main UI 'button'

    def set_button_border
      @frame.shadow_type = @config.hide_border? ? Gtk::SHADOW_NONE : Gtk::SHADOW_OUT;
    end

    # Accessor for the SSHMenu::ClassMapper singleton object

    def mapper
      ClassMapper.instance
    end

    # Thin wrapper around the Gtk.main loop

    def run
      return shell_run if @app_win == :none
      Gtk.main
    end

    # Run method for non-GUI actions.  Attempts to initiate a connection to
    # each host listed in ARGV.

    def shell_run
      return if ARGV.empty?
      ARGV.each do |name|
        open_win(@config.host_by_name(name))
      end
    end

    # Called from the constructor to check if the 'bcvi' program is installed
    # anywhere in the search path.  If bcvi is found then a checkbox will be
    # displayed in the host edit dialog.

    def check_for_bcvi
      path = ENV['PATH'] || ''
      path.split(':').each do |dir|
        file = Pathname.new(dir) + 'bcvi'
        if FileTest.executable?(file)
          @have_bcvi = true
          break
        end
      end
    end

    # Returns a boolean flag indicating whether the program is running in an
    # applet with context menu support.

    def context_menu_active?
      return @context_menu_active
    end

    # Accessor for the @have_bcvi attribute.

    def have_bcvi?
      return @have_bcvi
    end

    # Called from the constructor to set up default class mappings for
    # application components.

    def inject_defaults
      mapper.inject(
        'app.history'      => SSHMenu::History,
        'app.dialog.prefs' => SSHMenu::PrefsDialog,
        'app.dialog.host'  => SSHMenu::HostDialog,
        'app.dialog.menu'  => SSHMenu::MenuDialog,
        'app.geograbber'   => SSHMenu::GeoGrabber
      )
    end

    # Reads the config file. If no config file exists at all, calls
    # SSHMenu::Config#autoconfigure to invoke the configuration wizard.

    def get_initial_config
      if @config.not_configured?
        @config.autoconfigure
      end

      get_latest_config
    end

    # Called from the wrapper script to handle the parsing of command-line
    # options.  Calls getopt_defs to determine which options are recognised
    # and then calls the set_* method for each option as it is encountered
    # (eg: set_config_file).

    def getopts(argv)
      begin
        argv = argv.flatten      # Copy argument (which might already be ARGV)
        ARGV.clear               # Then copy contents into ARGV
        argv.each { |a| ARGV.push(a) }
        opts = GetoptLong.new( *getopt_defs )
        opts.quiet = true
        opts.each do |opt, arg|
          method = opt.gsub(/^-*/, 'set_').gsub(/\W/, '_')
          self.send(method, arg)
        end
        @options[:window] = :none if not ARGV.empty?
      rescue Exception => detail
        $stderr.puts detail.message
        exit 1
      end
    end

    # Returns a list of command-line option definitions for use by GetoptLong.

    def getopt_defs
      return(
        [
          [ "--version",           "-V",    GetoptLong::NO_ARGUMENT       ],
          [ "--debug",             "-d",    GetoptLong::OPTIONAL_ARGUMENT ],
          [ "--config-file",       "-c",    GetoptLong::REQUIRED_ARGUMENT ],
          [ "--socket-window-id",  "-s",    GetoptLong::REQUIRED_ARGUMENT ],
          [ "--list-completions",  "-l",    GetoptLong::NO_ARGUMENT       ]
        ]
      )
    end

    # Called by GetoptLong if the '--version' option was supplied.

    def set_version(arg)
      raise ShowVersionException
    end

    # Called by GetoptLong if the '--debug' option was supplied.

    def set_debug(level)
      level = 1 if level.to_s == ''
      @debug_level = level.to_i
    end

    # Called by GetoptLong if the '--config-file' option was supplied.

    def set_config_file(file)
      @config.set_config_file(file)
    end

    # Called by GetoptLong if the '--socket-window-id' option was supplied.

    def set_socket_window_id(window_id)
      @socket_window_id = window_id.to_i
    end

    # Called by GetoptLong if the '--list-completions' option was supplied.

    def set_list_completions(arg)
      defer_action { list_completions() }
      @options[:window] = :none
    end

    # Expects a single argument in ARGV after options have been processed.
    # Returns a list of possible expansions to host title definitions and
    # hostnames from the history file

    def list_completions()
      if prefix = ARGV.shift
        prefix = prefix.gsub(/\\(.)/, "\\1")
        chars = prefix.size
        seen  = { }
        @config.each_item() do |parents, item|
          if item.host? and item.title.slice(0,chars) == prefix
            if not seen[item.title]
              puts item.title
              seen[item.title] = true
            end
          end
        end
        @history.each_match(prefix, true) do |name|
          if not seen[name]
            puts name
            seen[name] = true
          end
        end
      end
      exit
    end

    # Called when the main application button is clicked.  Responds by
    # displaying the main menu.

    def on_click(widget, event)
       return show_hosts_menu(event)  if event.button == 1
       return false
    end

    # Takes a code block and schedules it to be called when option processing
    # is complete

    def defer_action(&action_proc)
      @deferred_actions.push action_proc
    end

    # Takes an exception object and displays the error message and the
    # backtrace using SSHMenu::App#alert.

    def App.fatal_error(exception)
      alert('Fatal error: ' + exception.message, exception.backtrace.join("\n"))
    end

    # Uses a pop-up dialog to display a message and optional further detail.

    def App.alert(message, extra_msg = nil)
      dialog = Gtk::Dialog.new(
        nil,
        nil,
        Gtk::Dialog::DESTROY_WITH_PARENT,
        [ Gtk::Stock::CLOSE, Gtk::Dialog::RESPONSE_NONE ]
      )
      dialog.has_separator = false
      stock_id = nil
      if message =~ /error/i
        dialog.title = 'Error'
        stock_id     = Gtk::Stock::DIALOG_ERROR
      else
        dialog.title = 'Warning'
        stock_id     = Gtk::Stock::DIALOG_WARNING
      end
      label = Gtk::Label.new(message)
      label.selectable = true
      icon  = Gtk::Image.new(stock_id, Gtk::IconSize::DIALOG)
      box = Gtk::HBox.new(false, 10)
      box.add(icon)
      box.add(label)
      box.border_width = 10
      dialog.vbox.add(box)
      if extra_msg
        expander = Gtk::Expander.new('Detail')
        expander.border_width = 10
        extra_label = Gtk::Label.new(extra_msg)
        extra_label.selectable = true
        expander.add(extra_label)
        dialog.vbox.add(expander)
      end
      dialog.screen = @@display if @@display
      dialog.show_all
      dialog.run
      dialog.destroy
    end

    # Proxy for SSHMenu::App#alert class method

    def alert(message, detail = nil)
      self.class.alert(message, detail)
    end

    # Called by the main application button click handler.  Makes sure the
    # latest config data has been loaded; constructs a menu from that config
    # and displays the menu.

    def show_hosts_menu(event)
      get_latest_config

      mif = Gtk::ItemFactory.new(Gtk::ItemFactory::TYPE_MENU, "<main>", nil)

      @config.each_item() do |parents, item|
        if item.host?
          menu_add_host(mif, parents, item)
        elsif item.separator?
          menu_add_separator(mif, parents, item)
        elsif item.menu?
          if menu_add_menu_options(mif, parents, item)
            sep_path = item_path(parents, item) + '/<opt_sep>'
            mif.create_item(sep_path, '<Separator>')
          end
        end
      end

      add_tools_menu_items(mif)

      menu = mif.get_widget('<main>')
      menu.screen = @@display
      menu.popup(nil, nil, event.button, event.time){ menu_position(menu, event) }

      return false  # allow button press handling to continue
    end

    # Called from show_hosts_menu to add a separator to the menu

    def menu_add_separator(mif, parents, item)
      mif.create_item(item_path(parents, item), '<Separator>')
    end

    # Called from show_hosts_menu to add a host to the menu

    def menu_add_host(mif, parents, item)
      mif.create_item(item_path(parents, item), "<Item>") { open_win(item) }
    end

    # Called from show_hosts_menu to add the optional parts at the
    # top of a sub-menu:
    # * a 'tear off' strip
    # * an 'Open all windows' option

    def menu_add_menu_options(mif, parents, item)
      return unless item.has_children?
      need_sep = false
      if @config.menus_tearoff?
        mif.create_item(item_path(parents, item) + '/<tearoff>', '<Tearoff>')
      end
      if @config.menus_open_all?
        mif.create_item(
          item_path(parents, item) + '/Open all windows', "<Item>"
        ) { open_all(item) }
        need_sep = true
      end
      return need_sep
    end

    # Helper method for calculating menu item paths

    def item_path(parents, item)
      path = [parents, item].flatten.map do |i|
        i.title.gsub(/\//, '\/').gsub(/_/, '__')
      end
      return '/' + path.join('/')
    end

    # Called before the menu is displayed.  Ensures the latest config data
    # has been loaded.  This allows manual edits of the config file to be
    # reflected without having to restart the app.

    def get_latest_config
      begin
        @config.load
      rescue Exception => detail
        alert(
            "Error reading config file: #{@config.filename}",
            detail.message + "\n" + detail.backtrace.join("\n")
        )
      end
    end

    # Adds the menu selections at the bottom of the main menu:
    # * preferences dialog
    # * add SSH key to agent
    # * remove SSH keys from agent

    def add_tools_menu_items(mif)
      mif.create_item("/tools-separator", '<Separator>')

      if not context_menu_active?
        mif.create_item(
          "/Preferences", "<StockItem>", nil, Gtk::Stock::PROPERTIES
        ){ edit_preferences }
      end

      mif.create_item("/Add SSH key to Agent",       "<Item>") { add_key     }
      mif.create_item("/Remove SSH keys from Agent", "<Item>") { remove_keys }
    end

    # Helper method to calculate where to place the main menu

    def menu_position(menu, event)
      (w, h) = event.window.size
      x = event.x_root - event.x - 1
      y = event.y_root - event.y + h + 1

      # Correct if window is near bottom

      (mw, mh) = menu.size_request
      sh       = menu.screen.height
      sw       = menu.screen.width
      if y > 200 and y + mh > sh
        y = event.y_root - event.y - mh - 1
        y = 0 if y < 0
      end

      # Correct if window is near right

      if x > 200 and x + mw > sw
        x = sw - mw
        x = 0 if x < 0
      end

      return [x, y]
    end

    # Invoked if the user selects the 'Add SSH key to agent' option from the
    # main menu.  Attempts to set up the environment to allow an askpass dialog
    # window can be displayed and then runs the ssh-add command.

    def add_key
      return if @have_key

      if !ENV['SSH_AUTH_SOCK']
        alert("$SSH_AUTH_SOCK is not set.\nIs the ssh-agent running?")
        return
      end

      if !File.exists?(ENV['SSH_AUTH_SOCK'])
        alert(
          "$SSH_AUTH_SOCK points to #{ENV['SSH_AUTH_SOCK']},\n" +
          "but it does not exist!"
        )
        return
      end

      keylist = `ssh-add -l`
      if $? == 0
        @have_key = true
        return
      end

      setup_askpass_env or return
      shell_command("ssh-add </dev/null >/dev/null 2>&1")
    end

    # Helper method called from add_key.  Sets up the environment for an
    # askpass helper window.

    def setup_askpass_env
      if(ENV['SSH_ASKPASS'] and File.executable?(ENV['SSH_ASKPASS']))
        return true
      end

      AskpassPaths.each do |path|
        if File.executable?(path)
          ENV['SSH_ASKPASS'] = path
          return true
        end
      end

      alert(
        "Can't find ssh-askpass.\nPerhaps you need to install a package."
      )
      return false
    end

    # Invoked if the 'Remove SSH keys from agent' option is selected.  Runs
    # ssh-add -D.

    def remove_keys
      shell_command("ssh-add -D </dev/null >/dev/null 2>&1")
      @have_key = false
    end

    # Invoked if the user selects a host from the menu.  Yields the
    # SSHMenu::HostItem object to the wrapper script block if a block was
    # supplied, otherwise builds a command line with build_window_command and
    # executes it.

    def open_win(host)
      add_key
      if @launch_proc
        @launch_proc.call(host)
      else
        shell_command(build_window_command(host))
      end
    end

    # Invoked if the user selects 'Open all windows' from a sub-menu.  Does the
    # same as open_win but for each host on the menu.

    def open_all(menu)
      add_key
      menu.items.each do |item|
        if item.host?
          if @launch_proc
            @launch_proc.call(item)
          else
            shell_command(build_window_command(item))
          end
          sleep 0.1  # to avoid .xauth lock conflicts with parallel connects
        end
      end
    end

    # Takes a SSHMenu::HostItem object, builds a command line for invoking SSH
    # in an xterm window, to connect to the specified host.

    def build_window_command(host)
      command = "#{host.env_settings}xterm -T " + shell_quote(host.title)
      if host.geometry and host.geometry.length > 0
        command += " -geometry #{host.geometry}"
      end
      ssh_cmnd = ssh_command(host)
      command += ' -e sh -c ' +
                 shell_quote("#{ssh_cmnd} #{host.sshparams_noenv}") + ' &'
      return command
    end

    # Called from build_window_command to determine the name of the ssh command
    # to use to connect to the specified host.  Normally returns 'ssh' but if
    # the supplied SSHMenu::HostItem object has its enable_bcvi property set to
    # true then 'bcvi --wrap-ssh --' will be returned instead.

    def ssh_command(host)
      if host.enable_bcvi
        return 'bcvi --wrap-ssh --'
      else
        return 'ssh'
      end
    end

    # Helper routine used by build_window_command to transform a string into a
    # double-quoted string in which special characters have been escaped with
    # backslashes as per standard Bourne shell quoting rules.

    def shell_quote(string)
      return '"' + string.gsub(/([\\"$`])/, '\\\\\1') + '"'
    end

    # Called when the 'Preferences' option is selected from the main menu.
    # Instantiates an 'app.dialog.prefs' object and calls its invoke method
    # (SSHMenu::PrefsDialog#invoke by default).

    def edit_preferences
      dialog_class = mapper.get_class('app.dialog.prefs')
      dialog_class.new(self, @config).invoke
      show_hide_text_entry
      set_button_border
    end

    # Called from the SSHMenu::PrefsDialog if the user clicks on the home page
    # URL in the 'About' box.  Attempts to open the URL in a browser window.

    def open_homepage
      prog = browser_program or return
      shell_command("#{prog} #{SSHMenu.homepage_url}")
    end

    # Helper routine called from open_homepage.  Attempts to find a browser
    # program by looking for known browser executable names in each directory
    # in the search path.  Returns the name of the first program found.

    def browser_program
      progs = %w{ gnome-open sensible-browser firefox konqueror opera galeon }
      ENV['PATH'].split(':').each do |dir|
        progs.each do |p|
          path = "#{dir}/#{p}"
          return path if FileTest.executable?(path)
        end
      end
      alert(
        'Unable to locate a web browser program',
        "Tried:\n#{progs.join(', ')}"
      )
      return
    end

    # Run a shell command via 'system'.  Optionally print command to STDOUT
    # if debugging is enabled.

    def shell_command(command)
      debug(1, "shell_command(#{command})");
      system(command);
    end

    # Output diagnostic information to STDOUT if debugging is enabled

    def debug(level, message)
      return if @debug_level < level
      puts message
    end

    # Debian's 'popcon' (Popularity Contest) normally reports the sshmenu
    # package as 'installed but not used' since the panel applet does not
    # access /usr/bin/sshmenu.  This routine updates the atime on that file
    # each time the applet starts.  This functionality is completely
    # non-essential and can be safely disabled in the unlikely event that it
    # causes some problem.

    def appease_popcon   # :nodoc:
      begin
        open('/usr/bin/sshmenu') { |f| f.readline }
      rescue Exception
      end
    end

  end


  ############################################################################
  # The SSHMenu::Config class implements the data model for the application.
  # It is responsible for:
  # * reading the configuration file
  # * maintaining an in-memory representation of the menu items and option
  #   settings
  # * writing the config file if changes are made via the preferences dialog
  #
  # The ClassMapper is used to delegate chunks of functionality to different
  # classes as follows:
  #
  # ['app.model.item'     => SSHMenu::Item]         base class for menu items
  #                                                 (including separators)
  # ['app.model.hostitem' => SSHMenu::HostItem]     host menu items
  # ['app.model.menuitem' => SSHMenu::MenuItem]     sub-menu items
  # ['app.model.autoconf' => SSHMenu::SetupWizard]  initial setupwizard
  #

  class Config

    # pathname of user's config file ($HOME/.sshmenu)
    attr_reader  :filename

    DefaultTooltip = 'Open an SSH session in a new window'

    # Called from SSHMenu::Factory#make_app.  Calls load_classes and
    # inject_defaults to set up any class mapping overrides defined in the
    # config file.

    def initialize(args = {})
      @globals    = { 'tooltip' => DefaultTooltip }
      @menu_items = [ ]
      @home_dir   = nil # suppress warning message
      @timestamp  = nil
      @classes    = { }

      if args[:filename]
        @filename = args[:filename]
      else
        @filename = home_dir + '.sshmenu'
      end

      load_classes
      inject_defaults
    end

    # Accessor for the SSHMenu::ClassMapper singleton object

    def mapper
      ClassMapper.instance
    end

    # Called from the constructor to set up default class mappings for
    # menu item classes and the setup wizard.

    def inject_defaults
      mapper.inject(
        'app.model.item'     => SSHMenu::Item,
        'app.model.hostitem' => SSHMenu::HostItem,
        'app.model.menuitem' => SSHMenu::MenuItem,
        'app.model.autoconf' => SSHMenu::SetupWizard
      )
    end

    # Returns the user's home directory which will be determined either from
    # the $HOME environment variable or from the user's entry in /etc/passwd.

    def home_dir
      return @home_dir unless @home_dir.nil?
      if ENV['HOME']
        return @home_dir = Pathname.new(ENV['HOME'])
      end
      require 'etc'
      if name = Etc.getlogin
        info = Etc.getpwnam(name)
        return @home_dir = Pathname.new(info.dir) if info.dir
      end
      raise "$HOME is not defined"
    end

    # Used to override the default config file (e.g.: call from
    # SSHMenu::App#set_config_file during commandline option parsing).

    def set_config_file(file)
      @filename = file
    end

    # Returns true if the .sshmenu config file has not been created yet.

    def not_configured?
      return !File.exists?(@filename)
    end

    # Called to invoke the setup wizard

    def autoconfigure
      wizard = mapper.get_class('app.model.autoconf')
      a = wizard.new.autoconfigure(self) or return
      set_items_from_array(a)
    end

    # Reads the 'classes' section from the config file.  If a 'require' key
    # is defined, the specified file is 'required'.  Any remaining keys are
    # passed to the SSHMenu::ClassMapper.  The remainder of the config file
    # is ignored by this routine.

    def load_classes
      classes = nil
      begin
        config  = YAML.load_file(@filename)
        classes = config['classes'] or return
      rescue
        return
      end
      if source_file = classes.delete('require')
        begin
          require source_file
        rescue Exception => detail
          raise "Error in 'require': #{detail}"
        end
      end
      classes.each do |k,v|
        cls = eval "class #{v}\nend\n#{v}" # turn string into a Class
        mapper.inject(k => cls)
      end
    end

    # Reads the config file and creates an in-memory representation of the
    # configuration.  May be called multiple times during the life of the
    # process (e.g.: if the file is modified).  Any config read from the file
    # will replace in-memory config data.

    def load
      if not_configured?
        save
        return
      end

      mtime = File.mtime(@filename)
      if !@timestamp.nil?
        return if mtime == @timestamp
      end

      config   = YAML.load_file(@filename) || {}

      @globals = config['global']  || {}
      @classes = config['classes'] || {}

      a = config['items'] || config['item'] || []
      set_items_from_array(a)

      @globals['tooltip'] ||= DefaultTooltip

      @timestamp = mtime
    end

    # Helper routine to translate the array of menu items from the config file
    # into SSHMenu::Item objects.

    def set_items_from_array(a)
      item_class = mapper.get_class('app.model.item')
      @menu_items = item_class.new_from_array(a)
    end

    # Serialises the menu items and global settings to hashes and writes them
    # all back out to the config file in YAML format.

    def save
      make_backup_copy if back_up_config?
      fh = File.new(@filename, 'w')
      config = {
        'global'  => @globals,
        'classes' => @classes,
        'items'   => @menu_items.map { |i| i.to_h }
      }
      fh.print YAML.dump(config)
      fh.close
      mtime = File.mtime(@filename)
      @timestamp = mtime
    end

    # Called to copy the config file to .sshmenu.bak before the original is
    # overwritten.

    def make_backup_copy
      return unless File.exists?(@filename)
      File.syscopy(@filename, @filename.to_s + '.bak')
    end

    # Gets the value of an attribute in the 'globals' config section

    def get(key, default = nil)
      return default unless @globals.has_key?(key)
      return @globals[key]
    end

    # Sets the value of an attribute in the 'globals' config section

    def set(key, value)
      @globals[key] = value
    end

    # Returns the value of the 'tooltip' global attribute

    def tooltip_text
      return @globals['tooltip']
    end

    # Returns true if the 'hide button border' option is enabled

    def hide_border?
      if opt = get('hide_border')
        return opt != 0
      end
      return false
    end

    # Sets the state of the 'hide button border' option

    def hide_border=(val)
      set('hide_border', val ? 1 : 0)
    end

    # Returns true if the 'tear-off menus' option is enabled

    def menus_tearoff?
      if opt = get('menus_tearoff')
        return opt != 0
      end
      return false
    end

    # Sets the state of the 'tear-off menus' option

    def menus_tearoff=(val)
      set('menus_tearoff', val ? 1 : 0)
    end

    # Returns true if the 'Open all windows' option is enabled

    def menus_open_all?
      if opt = get('menus_open_all')
        return opt != 0
      end
      return false
    end

    # Sets the state of the 'Open all windows' option

    def menus_open_all=(val)
      set('menus_open_all', val ? 1 : 0)
    end

    # Returns true if the 'show text entry' option is enabled

    def show_entry?
      if opt = get('show_entry')
        return opt != 0
      end
      return false
    end

    # Sets the state of the 'show text entry' option

    def show_entry=(val)
      set('show_entry', val ? 1 : 0)
    end

    # Returns true if the 'Backup on save' option is enabled

    def back_up_config?
      if opt = get('back_up_config')
        return opt != 0
      end
      return false
    end

    # Sets the state of the 'Backup on save' option

    def back_up_config=(val)
      set('back_up_config', val ? 1 : 0)
    end

    # Creates and returns a Host item from a simple hostname string

    def host_from_text(text)
      item_class = mapper.get_class('app.model.item')
      return item_class.new_from_hash({
        'type'      => 'host',
        'title'     => text,
        'sshparams' => text
      })
    end

    # Returns a Host item for the supplied name, either by locating the first
    # host definition with a title match, or by using the name as a hostname

    def host_by_name(name)
      each_item() do |parents, item|
        return item if item.host? and item.title == name
      end
      return host_from_text(name)
    end

    # Takes a host item, appends it to the main menu and saves the result

    def append_host(item)
      @menu_items.push(item)
      self.save
    end

    # Iterator for walking the tree of menu items as a depth first traversal.

    def each_item(&action)  # :yields: parent_items, item
      parents = []
      iterate_items(@menu_items, parents, action)
    end

    private

      def iterate_items (a, parents, action)
        a.each { |i|
          action.call(parents,i)
          if i.menu?
            parents.push i
            iterate_items(i.items, parents, action)
            parents.pop
          end
        }
      end

  end

  ############################################################################
  # SSHMenu::Item acts as a base for the SSHMenu::HostItem and
  # SSHMenu::MenuItem classes and also is used to represent menu separator
  # items.

  class Item

    # e.g.: 'separator', 'host' or 'menu'
    attr_reader :type

    # Default constructor.

    def initialize(type)
      @type = type
    end

    # Called from SSHMenu::Config#set_items_from_array to construct item objects
    # from the array of hashes in the config file.

    def Item.new_from_array(a)
      items = []
      a.each { |h| items.push self.new_from_hash(h) }
      return items
    end

    # Alternate constructor.  Based on the value of 'type' in the supplied
    # hash, delegates construction to SSHMenu::HostItem or SSHMenu::MenuItem.

    def Item.new_from_hash(h)
      type = h['type'] || ''
      mapper = ClassMapper.instance
      if type == 'separator'
        return mapper.get_class('app.model.item').new('separator')
      elsif type == 'host'
        return mapper.get_class('app.model.hostitem').new(h)
      elsif type == 'menu'
        return mapper.get_class('app.model.menuitem').new(h)
      else
        puts "Ignoring item of unknown type '#{type}'"
      end
    end

    # Provides a default title (overridden by host and menu items).

    def title
      return "Item #{object_id}"
    end

    # Returns true if the item is of type 'host'.

    def host?
      return @type == 'host'
    end

    # Returns true if the item is of type 'menu'.

    def menu?
      return @type == 'menu'
    end

    # Returns true if the item is of type 'separator'.

    def separator?
      return @type == 'separator'
    end

    # Serialises the item to a hash (overridden by derived classes).

    def to_h
      return { 'type' => @type }
    end

  end

  ############################################################################
  # The SSHMenu::HostItem is used as a container for the configuration options
  # associated with a host item on the main menu.
  #
  # Accessors are provided for the following properties (corresponding to
  # input elements in the 'Edit Host' dialog):
  # * title
  # * sshparams
  # * geometry
  # * enable_bcvi
  #
  # Inherits from SSHMenu::Item.

  class HostItem < Item

    # Defines a list of attribute names for which accessor methods are generated

    def HostItem.attributes
      [ :title, :sshparams, :geometry, :enable_bcvi ]
    end

    # Generates accessor methods

    def HostItem.make_accessors
      self.attributes.each { |a| attr(a, true) }
    end

    make_accessors

    # Typically called from SSHMenu::Item#new_from_hash.  Retains a copy of
    # the whole attributes hash, allowing unrecognised attributes from the
    # config file to be retained.
    #
    # :call-seq:
    #   SSHMenu::HostItem.new(attributes) -> SSHMenu::HostItem
    #

    def initialize(h={})
      @type = 'host'
      @hash = h.dup
      self.class.attributes.each { |a| self.send("#{a}=", h[a] || h[a.to_s]) }
    end

    # Returns a deep copy of the current host item.

    def dup
      self.class.new(to_h)
    end

    # Serialises the host item to a hash (including keys for any unknown
    # attributes which were read in from the config file).

    def to_h
      h = @hash
      h['type'] = 'host'
      self.class.attributes.each { |a| h[a.to_s] = self.send(a) }
      h.delete('enable_bcvi') unless enable_bcvi
      return h
    end

    # Returns the initial part of the 'sshparams' property which defines
    # environment settings - may be an empty string.

    def env_settings
      return sshparams =~ /^((?:\w+="(?:\\"|[^"])*" +)*)/ ? $1 : ''
    end

    # Returns the 'sshparams' property without the initial environment settings
    # section.

    def sshparams_noenv
      return sshparams =~ /^(?:\w+="(?:\\"|[^"])*" +)*(.*)$/ ? $1 : ''
    end

  end

  ############################################################################
  # The SSHMenu::MenuItem is used as a container for the configuration options
  # associated with a sub-menu.  The object's only properties are the title
  # and the array of child items.  Inherits from SSHMenu::Item.

  class MenuItem < Item

    # An array of SSHMenu::Item children.
    attr_reader   :items

    # The menu title.
    attr_accessor :title

    # Constructor.  Attributes hash should contain 'title' and 'items' keys.
    # Any other keys will be discarded.
    #
    # :call-seq:
    #   SSHMenu::MenuItem.new(attributes) -> SSHMenu::MenuItem
    #

    def initialize(h={})
      @type  = 'menu'
      @title = h['title'] || ''
      @items = []
      mapper = ClassMapper.instance
      item_class = mapper.get_class('app.model.item')
      (h['items'] || []).each { |h| @items.push item_class.new_from_hash(h) }
    end

    # Returns true if the menu contains any items (i.e.: is not empty).

    def has_children?
      @items.length > 0
    end

    # Discards all child items.

    def clear_items
      @items = []
    end

    # Adds a new item onto the end of the list of children.

    def append_item(item)
      @items.push item
    end

    # Serialises the menu title and child items to a hash.

    def to_h
      return {
        'type'  => 'menu',
        'title' => @title,
        'items' => @items.map { |i| i.to_h }
      }
    end

  end

  ############################################################################
  # SSHMenu::History manages the history of hostnames entered in the quick-
  # connect entry box.

  class History

    # Constructor, expects a single argument: the config object

    def initialize(config)
      @hist_file = config.home_dir + '.sshmenu_history'
      @timestamp = nil
      load_history
    end

    # Reads lines from the history file into memory

    def load_history
      @history = []
      if File.readable?(@hist_file)
        @history = @hist_file.readlines.collect{|l| l.chomp}
        @timestamp = File.mtime(@hist_file)
      end
    end

    # Reloads the history file if it has been modified

    def freshen
      return unless File.exists?(@hist_file)
      load_history if File.mtime(@hist_file) != @timestamp
    end

    # Adds a line to the start of the history list and then saves the list to
    # the history file

    def add_line(line)
      @history = [ line, @history.find_all { |l| l != line } ].flatten
      fh = File.new(@hist_file, 'w')
      @history.each { |l| fh.puts(l) }
      fh.close
      @timestamp = File.mtime(@hist_file)
    end

    # Iterator which yields a list of history strings which match the supplied
    # text string

    def each_match(text, prefix_only = false)
      pattern = Regexp.quote(text)
      @history.each do |line|
        yield(line) if line =~ /^#{pattern}/i  # match at start
      end
      if not prefix_only
        @history.each do |line|
          next if line =~ /^#{pattern}/i
          yield(line) if line =~ /#{pattern}/i   # match, but not at start
        end
      end
    end

  end


  ############################################################################
  # The SSHMenu::PrefsDialog class implements the main preferences dialog.
  # Current config is read in from the 'app.model' object and written back if
  # the user chooses to save a new config.
  #
  # The dialog user interface comprises a treeview for the menu items and
  # buttons for adding, removing, editing and reordering items.
  #
  # Two additional tabs provide access to global option settings and the
  # 'About' box.

  class PrefsDialog

    ItemColumn = 0

    # Constructor.  Takes an application object for global constants and a
    # config object for reading/writing the configuration.

    def initialize(app, config)
      @app       = app
      @config    = config
      @button    = { }
      @prev_path = nil
      @next_path = nil
    end

    # Accessor for the SSHMenu::ClassMapper singleton object

    def mapper
      ClassMapper.instance
    end

    # Creates the main dialog, waits for it to be dismissed and saves the
    # contents if 'OK' was clicked.

    def invoke
      dialog = build_dialog

      if dialog.run != Gtk::Dialog::RESPONSE_ACCEPT
        dialog.destroy
        return
      end

      (w, h) = dialog.size
      @config.set('width',  w)
      @config.set('height', h)

      save_menu_items
      save_options

      dialog.destroy

      @config.save
    end

    # Helper routine which transfers the host items from the treeview widget
    # back to the config object.

    def save_menu_items
      items = []

      @model.each do |model, path, iter|
        i = iter[ItemColumn]
        i.clear_items if i.menu?
        if path.depth > 1
          parent = iter.parent[ItemColumn]
          parent.append_item(i)
        else
          items.push i
        end
      end

      @config.set_items_from_array(items.collect { |i| i.to_h })
    end

    # Helper routine which transfers global option settings back to the config
    # object.

    def save_options
      if @app.can_show_entry?
        @config.show_entry   = @chk_show_entry.active?
      end
      @config.hide_border    = @chk_hide_border.active?
      @config.menus_tearoff  = @chk_tearoff.active?
      @config.menus_open_all = @chk_open_all.active?
      @config.back_up_config = @chk_back_up_config.active?
    end

    # Called from the invoke method to assemble the widgets in the dialog.

    def build_dialog
      dialog = Gtk::Dialog.new(
        "Preferences",
        nil,
        Gtk::Dialog::MODAL | Gtk::Dialog::DESTROY_WITH_PARENT | Gtk::Dialog::NO_SEPARATOR,
        [Gtk::Stock::OK, Gtk::Dialog::RESPONSE_ACCEPT],
        [Gtk::Stock::CANCEL, Gtk::Dialog::RESPONSE_REJECT]
      )
      dialog.window_position = Gtk::Window::POS_MOUSE

      w = @config.get('width')  || 370
      h = @config.get('height') || 360
      dialog.resize(w, h)
      dialog.screen = @app.display

      notebook = Gtk::Notebook.new
      dialog.vbox.pack_start(notebook, true, true, 0)

      notebook.append_page(
        make_hosts_pane,
        Gtk::Label.new("_Hosts", true)
      )

      notebook.append_page(
        make_options_pane(),
        Gtk::Label.new("O_ptions", true)
      )

      if not @app.context_menu_active?
        notebook.append_page(
          @app.make_about_pane(),
          Gtk::Label.new("Abou_t", true)
        )
      end

      dialog.show_all

      return dialog
    end

    # Called from build_dialog to construct the contents of the main tab.

    def make_hosts_pane
      pane = Gtk::HBox.new(false, 12)
      pane.set_border_width(8)

      list_box = Gtk::VBox.new(false, 8)
      pane.pack_start(list_box, true, true, 0)

      sw = Gtk::ScrolledWindow.new
      sw.set_shadow_type(Gtk::SHADOW_ETCHED_IN)
      sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      list_box.pack_start(sw, true, true, 0)

      hlist = make_hosts_list()
      sw.add(hlist)
      hlist.signal_connect('row_activated') { btn_edit_pressed }

      arrows = Gtk::HBox.new(true, 10)
      list_box.pack_start(arrows, false, true, 0)

      buttons = Gtk::VBox.new(false, 10)
      pane.pack_start(buttons, false, true, 0)

      add_button(arrows,  'up',   '',               Gtk::Stock::GO_UP,   false)
      add_button(arrows,  'down', '',               Gtk::Stock::GO_DOWN, false)
      add_button(buttons, 'add',  '_Add Host',      nil,                 true)
      add_button(buttons, 'sep',  'Add _Separator', nil,                 true)
      add_button(buttons, 'menu', 'Add Sub_menu',   nil,                 true)
      add_button(buttons, 'edit', '_Edit',          nil,                 false)
      add_button(buttons, 'copy', 'Cop_y Host',     nil,                 false)
      add_button(buttons, 'del',  '_Remove',        nil,                 false)

      return pane
    end

    # Called from build_dialog to construct the contents of the global options
    # tab.

    def make_options_pane
      table = Gtk::Table.new(1, 1, false)
      table.set_border_width(10)
      r = 0

      if @app.can_show_entry?
        @chk_show_entry = Gtk::CheckButton.new(
          'show text _entry next to menu button', true
        )
        @chk_show_entry.active = @config.show_entry?
        table.attach(
          @chk_show_entry, 0, 1, r, r+1, Gtk::EXPAND|Gtk::FILL, Gtk::FILL, 0, 0
        )
        r += 1
      end

      @chk_back_up_config = Gtk::CheckButton.new(
        '_back up config file on save', true
      )
      @chk_back_up_config.active = @config.back_up_config?
      table.attach(
        @chk_back_up_config, 0, 1, r, r+1, Gtk::EXPAND|Gtk::FILL, Gtk::FILL, 0, 0
      )
      r += 1

      @chk_tearoff = Gtk::CheckButton.new('enable tear-off _menus', true)
      @chk_tearoff.active = @config.menus_tearoff?
      table.attach(
        @chk_tearoff, 0, 1, r, r+1, Gtk::EXPAND|Gtk::FILL, Gtk::FILL, 0, 0
      )
      r += 1

      @chk_hide_border = Gtk::CheckButton.new('hide button _border', true)
      @chk_hide_border.active = @config.hide_border?
      table.attach(
        @chk_hide_border, 0, 1, r, r+1, Gtk::EXPAND|Gtk::FILL, Gtk::FILL, 0, 0
      )
      r += 1

      @chk_open_all = Gtk::CheckButton.new(
        'include "Open all _windows" selection', true
      )
      @chk_open_all.active = @config.menus_open_all?
      table.attach(
        @chk_open_all, 0, 1, r, r+1, Gtk::EXPAND|Gtk::FILL, Gtk::FILL, 0, 0
      )

      return table
    end

    # Called from make_hosts_pane to construct the treeview widget and populate
    # it with host and sub-menu items

    def make_hosts_list
      @model = Gtk::TreeStore.new(SSHMenu::Item)

      @view = Gtk::TreeView.new(@model)
      @view.rules_hint    = false
      @view.search_column = 0

      if GLib.check_binding_version?(0, 19, 0)
        @view.reorderable = true
      end

      renderer = Gtk::CellRendererText.new

      column = Gtk::TreeViewColumn.new("Host", renderer)
      @view.append_column(column)
      column.set_cell_data_func(renderer) do |tvc, renderer, model, iter|
        i = iter[ItemColumn]
        if i.separator?
          renderer.text = "_____________________________"
        else
          renderer.text = i.title
        end
      end

      @view.selection.signal_connect('changed') {
        on_selection_changed(@view.selection.selected)
      }

      path = {}
      @config.each_item() do |parents, i|
        key = i.object_id
        parent = nil
        parent = @model.get_iter(path[parents[-1].object_id]) if parents.length > 0
        row = @model.append(parent)
        row[ItemColumn] = i.dup
        path[key] = row.path
      end

      @view.signal_connect('drag-drop') do
        Gtk.timeout_add(50) { fix_dropped_items }
        false
      end

      return @view.collapse_all
    end

    # Called from make_hosts_pane to add each of the dialog buttons and hook
    # up a signal handler for the 'clicked' event.

    def add_button(box, key, label, stock_id, sensitive)
      button =
        if stock_id
          @button[key] = Gtk::Button.new(stock_id)
        else
          @button[key] = Gtk::Button.new(label)
        end

      button.signal_connect('clicked') { send("btn_#{key}_pressed") }
      button.focus_on_click = false
      button.sensitive = sensitive
      box.pack_start(button, false, true, 0)
    end

    # Called from button handler routines to add items to the treeview.  The
    # new 'item' is inserted after an existing item identified by the iter
    # 'prev'.

    def add_item(prev, item)
      parent = nil
      iter =
        if prev.nil?
          @model.append(nil)
        elsif prev[ItemColumn].menu?
          parent = prev
          @model.append(prev)
        else
          parent = prev.parent
          @model.insert_after(parent, prev)
        end
      iter[ItemColumn] = item
      @view.expand_row(parent.path, false) if parent
      return iter
    end

    # Handler for the 'Changed' signal from the host list treeview.
    # Enables/disables buttons as appropriate.

    def on_selection_changed(iter)
      return unless iter
      @selected = iter.path
      item = get_item(iter)
      @button['edit'].sensitive = (item.host?  or  item.menu?)
      @button['copy'].sensitive = (item.host?)
      if iter[ItemColumn].menu? and iter.has_child?
        @button['del'].sensitive  = false
      else
        @button['del'].sensitive  = true
      end
      find_prev_next(iter)
      @button['up'].sensitive   = !@prev_path.nil?
      @button['down'].sensitive = !@next_path.nil?
    end

    # Helper routine for SSHMenu::PrefsDialog#on_selection_changed.  Locates
    # item before and item following selected item and stores these values for
    # calculating button sensitivity.

    def find_prev_next(target)
      @prev_path = nil
      @next_path = nil
      targ_path  = target.path
      found = false
      @model.each do |model, path, iter|
        if found
          if @next_path.nil?  and  !path.descendant?(targ_path)
            @next_path = path
          end
        elsif iter == target
          found = true
        else
          @prev_path = path
        end
      end

      if @next_path.nil? and !target.parent.nil?       # Target was last item
        if targ_path.up!
          @next_path = targ_path.next!
        end
      end
    end

    # Returns the menu item (separator, host or sub menu) identified by the
    # specified iter.

    def get_item(iter)
      return iter[ItemColumn]
    end

    # Returns an iter for the currently selected item.

    def selected_iter
      return @view.selection.selected
    end

    # Handler method for the 'Up' button.  Exchanges the current and previous
    # items in the treeview.

    def btn_up_pressed
      return unless @prev_path
      cur = selected_iter or return
      new_path = nil
      path_before = cur.path
      path_before.prev!
      if cur.path.to_str =~ /:0$/                      # First child in submenu
        parent   = @model.get_iter(@prev_path).parent
        sibling  = @model.get_iter(@prev_path)
        new_iter = @model.insert_before(parent, sibling)
        move_branch(cur, new_iter)
        @model.remove(cur)
        new_path = new_iter.path
      elsif @prev_path.to_str != path_before.to_str    # Move up into submenu
        parent   = @model.get_iter(@prev_path).parent
        @view.expand_row(parent.path, false)
        sibling  = @model.get_iter(@prev_path)
        new_iter = @model.insert_after(parent, sibling)
        move_branch(cur, new_iter)
        @model.remove(cur)
        new_path = new_iter.path
      elsif @model.get_iter(@prev_path)[ItemColumn].menu?  # Move up into empty menu
        parent   = @model.get_iter(@prev_path)
        new_iter = @model.append(parent)
        @view.expand_row(parent.path, false)
        move_branch(cur, new_iter)
        @model.remove(cur)
        new_path = new_iter.path
      else                                             # Swap with following peer
        new_path = cur.path
        new_path.prev! or return
        prv = @model.get_iter(new_path)
        @model.swap(prv, cur)
      end
      sel = @view.selection
      sel.unselect_all
      sel.select_path(new_path)
      @view.scroll_to_cell(new_path, nil, false, 0, 0)
    end

    # Handler method for the 'Down' button.  Exchanges the current and next
    # items in the treeview.

    def btn_down_pressed
      cur = selected_iter or return
      new_path = nil
      nxt_item = nil
      nxt = @model.get_iter(@next_path)
      if nxt
        nxt_item = nxt[ItemColumn] or return
      end
      path_after = cur.path
      path_after.next!
      if nxt_item and nxt_item.menu?                   # Move down into submenu
        parent = nxt
        nxt = nxt.first_child
        if nxt
          nxt = @model.insert_before(parent, nxt)
        else
          nxt = @model.append(parent)
        end
        @view.expand_row(parent.path, false)
        new_path = cur.path
        move_branch(cur, nxt)
        @model.remove(cur)
        new_path.down!
      elsif @next_path.to_str != path_after.to_str     # Move down out of submenu
        sibling = cur.parent
        parent  = sibling.parent
        nxt = @model.insert_after(parent, sibling)
        new_path = nxt.path
        move_branch(cur, nxt)
        @model.remove(cur)
      else                                             # Swap with preceding peer
        nxt = @model.get_iter(@next_path)
        new_path = @next_path
        @model.swap(cur, nxt)
      end
      sel = @view.selection
      sel.unselect_all
      sel.select_path(new_path)
      @view.scroll_to_cell(new_path, nil, false, 0, 0)
    end

    # Helper method for moving a TreeStore row along with all its children.

    def move_branch(src, dst)
      dst[ItemColumn] = src[ItemColumn]
      child_src = src.first_child
      while child_src
        child_dst = @model.append(dst)
        move_branch(child_src, child_dst)
        child_src.next! or break
      end
      @view.expand_row(dst.path, false) if @view.row_expanded?(src.path)
    end

    # Handler method for the 'Edit' button.  Pops up the Edit Host dialog for
    # the currently selected host item.

    def btn_edit_pressed
      iter = selected_iter or return
      item = get_item(iter)
      if item.host?
        edit_host(item)
      elsif item.menu?
        edit_menu(item)
      end
    end

    # Handler method for the 'Copy' button.  Pops up the Edit Host dialog with
    # fields populated from the currently selected item.

    def btn_copy_pressed
      iter = selected_iter or return
      item = get_item(iter).dup
      result = edit_host(item) or return
      iter = add_item(iter, result)
      @view.selection.select_iter(iter)
    end

    # Handler method for the 'Add Host' button.  Pops up the Edit Host dialog
    # with all fields blank.

    def btn_add_pressed
      item = mapper.get_class('app.model.hostitem').new
      result = edit_host(item) or return
      iter = add_item(selected_iter, item)
      @view.selection.select_iter(iter)
    end

    # Handler method for the 'Add Separator' button.

    def btn_sep_pressed
      item_class = mapper.get_class('app.model.item')
      item = item_class.new_from_hash( { 'type' => 'separator' } )
      iter = add_item(selected_iter, item)
      @view.selection.select_iter(iter)
    end

    # Handler method for the 'Add Submenu' button.  Pops up the Edit Menu
    # Dialog with blank inputs.

    def btn_menu_pressed
      item = mapper.get_class('app.model.menuitem').new
      result = edit_menu(item) or return
      iter = add_item(selected_iter, item)
      @view.selection.select_iter(iter)
    end

    # Handler method for the 'Delete' button.  Removes the currently selected
    # item from the treeview.

    def btn_del_pressed
      iter = selected_iter
      path = iter.path
      @model.remove(iter)
      @button['up'].sensitive   = false
      @button['down'].sensitive = false
      @button['edit'].sensitive = false
      @button['copy'].sensitive = false
      @button['del'].sensitive  = false
      if @model.get_iter(path).nil?
        if !path.prev!
          if !path.up!
            return
          end
        end
      end
      @view.selection.select_path(path)
    end

    # Handler method for drag-and-drop reordering of items in the treeview.
    # Tries to clean up after bad things that happen when items are dropped in
    # unexpected places.

    def fix_dropped_items
      bad_path = nil
      @model.each do |model, path, iter|
        item = iter[ItemColumn]
        if !item.menu? and iter.has_child?
          bad_path = iter.path
        end
      end
      return unless bad_path
      iter = @model.get_iter(bad_path)
      item = iter[ItemColumn]
      child = iter.first_child or return
      target = child[ItemColumn]
      @model.remove(child)
      nxt = @model.insert_after(iter.parent, iter)
      nxt[ItemColumn] = target
      sel = @view.selection
      sel.unselect_all
      sel.select_iter(nxt)
      @view.scroll_to_cell(nxt.path, nil, false, 0, 0)
      return false
    end

    # Pops up the Edit Host dialog ('app.dialog.host' mapped to
    # SSHMenu::HostDialog by default).

    def edit_host(item)
      dialog_class = mapper.get_class('app.dialog.host')
      return dialog_class.new(@app, item, @config).invoke
    end

    # Pops up the Edit Menu dialog ('app.dialog.menu' mapped to
    # SSHMenu::MenuDialog by default).

    def edit_menu(item)
      dialog_class = mapper.get_class('app.dialog.menu')
      return dialog_class.new(@app, item).invoke
    end

    # Called independently of the preferences dialog to display a host edit
    # dialog.  On a successful edit, the new host will be appended to the main
    # menu.

    def append_host(item)
      result = edit_host(item) or return
      @config.append_host(result)
    end

  end


  ############################################################################
  # The SSHMenu::HostDialog class implements the dialog for editing a
  # SSHMenu::HostItem.  Once the HostDialog object has been constructed, its
  # invoke method is called to display the dialog.  When the user dismisses the
  # dialog, the invoke method will return nil on cancel or the edited host item
  # on OK.

  class HostDialog

    TestResponse = 42   # :nodoc: an arbitrary constant for the test button

    # Constructor expects the following arguments:
    # [app] the application object (SSHMenu::App)
    # [host] the host item to be edited (SSHMenu::HostItem)
    # [config] the application model object (SSHMenu::Config)

    def initialize(app, item, config)
      @app      = app
      @host     = item
      @config   = config
    end

    # Accessor for the SSHMenu::ClassMapper singleton object

    def mapper
      ClassMapper.instance
    end

    # Causes the dialog to be displayed.  The invoke method does not return
    # until the user dismisses the dialog.  If the user presses OK, the edited
    # host item will be returned, otherwise nil will be returned.

    def invoke
      dialog = build_dialog

      while true
        response = dialog.run
        if response == Gtk::Dialog::RESPONSE_ACCEPT
          break if inputs_valid?
        elsif response == TestResponse
          test_host
        else
          dialog.destroy
          return
        end
      end

      dialog_to_host(@host)

      dialog.destroy

      return @host
    end

    # Validation routine - blocks saving if the title or ssh params entry boxes
    # are empty.

    def inputs_valid?
       if @title_entry.text.strip.length == 0
         @app.alert('You must enter a title')
         return false
       end
       if @params_entry.text.strip.length == 0
         @app.alert('You must enter a hostname')
         return false
       end
       return true
    end

    # Copies values from the dialog input widgets back to attributes in the
    # host object.  If no host item is supplied, a new one will be created.

    def dialog_to_host(host=nil)
      host ||= mapper.get_class('app.model.hostitem').new
      host.title     = @title_entry.text
      host.sshparams = @params_entry.text
      host.geometry  = @geometry_entry.text
      host.enable_bcvi = @enable_bcvi.active? if @enable_bcvi
      return host
    end

    # Called when the 'Test' button is pressed.  Creates a temporary
    # SSHMenu::HostItem object from the current inputs and passes it to
    # SSHMenu::App#open_win.

    def test_host
      @app.open_win(dialog_to_host)
    end

    # Helper routine, called from the invoke method to construct the dialog
    # user interface.

    def build_dialog
      dialog = Gtk::Dialog.new(
        "Host Connection Details",
        nil,
        Gtk::Dialog::MODAL | Gtk::Dialog::DESTROY_WITH_PARENT,
        ['Test', TestResponse ],
        [Gtk::Stock::OK, Gtk::Dialog::RESPONSE_ACCEPT],
        [Gtk::Stock::CANCEL, Gtk::Dialog::RESPONSE_REJECT]
      )
      dialog.default_response = Gtk::Dialog::RESPONSE_ACCEPT
      dialog.window_position = Gtk::Window::POS_MOUSE
      dialog.screen = @app.display

      @body = Gtk::VBox.new(false, 0)
      @body.set_border_width(4)
      dialog.vbox.add(@body)

      add_title_input
      add_hostname_input
      add_geometry_input
      add_other_inputs

      dialog.show_all

      return dialog
    end

    # Helper for build_dialog which adds the 'Title' input and label to the
    # dialog.

    def add_title_input
      @title_entry = add_input('Title', @host.title, nil)
    end

    # Helper for build_dialog which adds the 'Hostname (etc)' input and label
    # to the dialog.

    def add_hostname_input
      @params_entry = add_input('Hostname (etc)', @host.sshparams, nil)
    end

    # Helper for build_dialog which adds the 'Geometry' input and label to the
    # dialog.

    def add_geometry_input
      box = Gtk::HBox.new(false, 4)

      @geometry_entry = entry = Gtk::Entry.new
      entry.text = @host.geometry || ''
      entry.activates_default = true
      box.pack_start(entry, true, true, 0)

      grabber = mapper.get_class('app.geograbber')
      btn = Gtk::Button.new('Grab')
      btn.sensitive = grabber.can_grab?
      btn.signal_connect('clicked') { grabber.grab { |g| entry.text = g } }
      box.pack_start(btn, false, false, 0)

      add_input('Geometry', @host.geometry, box)
    end

    # Helper for build_dialog which adds additional input widgets after the
    # geometry input.  By default, the method will call add_bcvi_checkbox if
    # 'bcvi' is installed.

    def add_other_inputs
      add_bcvi_checkbox if @app.have_bcvi?
    end

    # Helper for build_dialog which adds a checkbox for enabling 'bcvi'
    # forwarding.

    def add_bcvi_checkbox
      @enable_bcvi = Gtk::CheckButton.new( "Enable 'bcvi' forwarding?", false)
      @enable_bcvi.active = true if @host.enable_bcvi
      @body.pack_start(@enable_bcvi, false, true, 0)
    end

    # Helper method for adding labelled input boxes to the dialog.  The
    # arguments are:
    # [text] will be used to label the input widget
    # [content] will be used as the initial value for the input widget
    # [widget] can be supplied, otherwise a text entry will be created

    def add_input(text, content, widget)
      label = Gtk::Label.new(text)
      label.set_alignment(0, 1)
      @body.pack_start(label, false, true, 0)

      if !widget
        widget = Gtk::Entry.new
        widget.width_chars       = 36
        widget.text              = content || ''
        widget.activates_default = true
      end

      @body.pack_start(widget, false, true, 0)

      return widget
    end
  end


  ############################################################################
  # The SSHMenu::MenuDialog class implements the dialog for editing a
  # SSHMenu::MenuItem.  Once the MenuDialog object has been constructed, its
  # invoke method is called to display the dialog.  When the user dismisses the
  # dialog, the invoke method will return nil on cancel or the edited menu item
  # on OK.

  class MenuDialog

    # Constructor expects the following arguments:
    # [app] the application object (SSHMenu::App)
    # [menu] the menu item to be edited (SSHMenu::MenuItem)

    def initialize(app, menu)
      @app      = app
      @menu     = menu
    end

    # Causes the dialog to be displayed.  The invoke method does not return
    # until the user dismisses the dialog.  If the user presses OK, the edited
    # menu item will be returned, otherwise nil will be returned.

    def invoke
      dialog = build_dialog

      while true
        response = dialog.run
        if response == Gtk::Dialog::RESPONSE_ACCEPT
          break if inputs_valid?
        else
          dialog.destroy
          return
        end
      end

      @menu.title = @title_entry.text

      dialog.destroy

      return @menu
    end

    # Validation routine - blocks saving if the title input is empty.

    def inputs_valid?
       if @title_entry.text.strip.length == 0
         @app.alert('You must enter a title')
         return false
       end
       return true
    end

    # Helper routine, called from the invoke method to construct the dialog
    # user interface.

    def build_dialog
      dialog = Gtk::Dialog.new(
        "Submenu Name",
        nil,
        Gtk::Dialog::MODAL | Gtk::Dialog::DESTROY_WITH_PARENT,
        [Gtk::Stock::OK, Gtk::Dialog::RESPONSE_ACCEPT],
        [Gtk::Stock::CANCEL, Gtk::Dialog::RESPONSE_REJECT]
      )
      dialog.default_response = Gtk::Dialog::RESPONSE_ACCEPT
      dialog.window_position = Gtk::Window::POS_MOUSE

      @body = Gtk::VBox.new(false, 0)
      @body.set_border_width(4)
      dialog.vbox.add(@body)

      label = Gtk::Label.new('Title')
      label.set_alignment(0, 1)
      @body.pack_start(label, false, true, 0)

      widget = Gtk::Entry.new
      widget.width_chars       = 36
      widget.text              = @menu.title
      widget.activates_default = true

      @title_entry = widget

      @body.pack_start(widget, false, true, 0)

      dialog.show_all

      return dialog
    end

  end


  ############################################################################
  # The SSHMenu::GeoGrabber class wraps the external 'xwininfo' command to
  # 'grab' the geometry of a running window.  The user would typically press
  # 'Test' on the Edit Host dialog (SSHMenu::HostDialog) to pop up a window;
  # size and position the window; and then 'Grab' to populate the 'Geometry'
  # text entry.

  class GeoGrabber

    # Called from SSHMenu::HostDialog#add_geometry_input to determine whether
    # the 'Grab' button should be enabled.  Returns true if xwininfo is
    # available and false otherwise.

    def GeoGrabber.can_grab?
      @@xwininfo ||= nil

      if @@xwininfo.nil?
        @@xwininfo = ENV['PATH'].split(':').collect { |d|
          d + '/xwininfo'
        }.find { |p|
          File.executable?(p)
        }
      end
      return !@@xwininfo.nil?
    end

    # This method is the main entry point for the class.  It takes no arguments
    # and yields a geometry string on success.  The external 'xwininfo' program
    # is used to  retrieve the geometry details of a selected window.

    def GeoGrabber.grab # :yields: geometry
      return unless can_grab?
      `#{@@xwininfo}`.each_line do |l|
        if l.match(/-geometry\s+([\d+x-]+)/)
          yield $1
        end
      end
    end

  end


  ############################################################################
  # The SSHMenu::SetupWizard class is used only once - when the menu program is
  # first run and the config file does not yet exist.  The role of the 'wizard'
  # is to pull hostnames out of the user's .ssh/known_hosts file and add them
  # to the menu.  The user may chose to skip this process and manually add the
  # required hosts.
  #
  # Sadly this process turns out to be not very useful on systems with the
  # HashKnownHosts option is enabled.

  class SetupWizard

    # This is the main entry point.  The SSHMenu::Config class will construct a
    # SetupWizard object and then call this method on it.  This method will
    # call run_wizard to do the work and then return a list of
    # SSHMenu::HostItem objects (possibly an empty list).

    def autoconfigure(config)
      @imported             = {}
      @hashed_hosts_skipped = 0
      @known_hosts_file     = config.home_dir + '.ssh/known_hosts'
      return unless @known_hosts_file.readable?
      return unless run_wizard
      host_list = []
      @imported.keys.sort.each do |name|
        host_list << {
          'type'      => 'host',
          'title'     => name,
          'sshparams' => "-AX #{@imported[name]}"
        }
      end
      return host_list
    end

    # Creates a dialog by calling build_dialog.  Populates the body of the
    # dialog by calling setup_step_one and awaits user interaction.  Replaces
    # the body of the dialog by calling setup_step_two and repeats.  Returns
    # true if the process was completed or false if the user pressed cancel.

    def run_wizard
      @dialog  = build_dialog
      setup_step_one
      if @dialog.run != Gtk::Dialog::RESPONSE_ACCEPT
        @dialog.destroy
        return false
      end

      setup_step_two
      if @dialog.run != Gtk::Dialog::RESPONSE_ACCEPT
        @dialog.destroy
        return false
      end

      @dialog.destroy
      return true
    end

    # Sets up an introductory message describing the function of the wizard and
    # provides Next and Cancel buttons (cleverly disguised as 'Automatic Setup'
    # and 'Manual Setup' buttons respectively).

    def setup_step_one

      set_body(
        Gtk::Label.new(
          "The initial menu options can be created automatically\n" +
          "from your list of SSH known hosts.\n\n" +
          "Or, if you prefer, you can set up the menu manually."
        ).set_xalign(0)
      )

      set_buttons(
        ["Manual Setup",    Gtk::Dialog::RESPONSE_REJECT],
        ["Automatic Setup", Gtk::Dialog::RESPONSE_ACCEPT]
      )
    end

    # Sets up a progress bar and registers import_tick as an 'idle' handler to
    # do the work.  The user can 'Cancel' at any time and can click 'Finish'
    # once import_tick has processed the whole known_hosts file.

    def setup_step_two

      vbox = Gtk::VBox.new
      vbox.spacing = 10

      vbox.pack_start(
        Gtk::Label.new( "Importing known hosts.  Please wait ...").set_xalign(0)
      )

      progress = Gtk::ProgressBar.new
      vbox.pack_start(progress)
      set_body(vbox)

      set_buttons(
        ["Cancel", Gtk::Dialog::RESPONSE_REJECT],
        ["Finish", Gtk::Dialog::RESPONSE_ACCEPT]
      )

      @dialog.set_response_sensitive(Gtk::Dialog::RESPONSE_ACCEPT, false)

      @raw_hosts = nil
      Gtk.idle_add { import_tick(@dialog, progress) }
    end

    # Called from import_tick when all the known_hosts entries have been
    # processed.

    def setup_step_three(count)
      vbox = Gtk::VBox.new
      vbox.spacing = 10

      text = "#{count} host#{count == 1 ? '' : 's'} imported"
      if @hashed_hosts_skipped > 0
        text = text + " (#{@hashed_hosts_skipped} hashed hostnames were skipped)"
      end
      vbox.pack_start(
        Gtk::Label.new(text).set_xalign(0)
      )

      progress = Gtk::ProgressBar.new
      progress.fraction = 1.0
      vbox.pack_start(progress)
      set_body(vbox)

      set_buttons(
        ["Cancel", Gtk::Dialog::RESPONSE_REJECT],
        ["Finish", Gtk::Dialog::RESPONSE_ACCEPT]
      )
    end

    # Replaces the body of the wizard dialog box with the supplied widget.

    def set_body(widget)
      @body.each { |w| @body.remove(w) }
      @body.add(widget)
      @body.show_all
    end

    # Replaces the dialog's button box contents with the supplied list of
    # buttons.  Each button is represented as a two element array.  The first
    # element is the button text label and the second is the response code the
    # button should generate.

    def set_buttons(*buttons)
      bbox = @dialog.action_area
      bbox.each { |w| bbox.remove(w) }
      buttons.each { |b| @dialog.add_button(*b) }
      @dialog.default_response = buttons.last[1]
    end

    # This routine does the work of processing the known hosts file and
    # updating the progress bar.  It is an 'idle handler' so it is called
    # multiple times until it returns false to indicate no further work
    # remains.  Calls list_host_aliases on the first invocation to get a list
    # of raw host aliases.  Each subsequent invocation processes one raw
    # host entry to resolve names and addresses (for duplicate filtering).

    def import_tick(dialog, progress)
      if @raw_hosts.nil?
        @raw_hosts = list_host_aliases
        @curr_host = 0
        progress.fraction = (@curr_host + 1.0) / (@raw_hosts.length + 1.0)
        return true
      end

      if @curr_host >= @raw_hosts.length
        setup_step_three(@raw_hosts.length)
        return false  # no more work to do
      end

      aliases = @raw_hosts[@curr_host]
      @curr_host += 1
      name = best_alias(aliases)
      addr = best_address(name, *aliases)
      @imported[name] = addr
      progress.fraction = (@curr_host + 1.0) / (@raw_hosts.length + 1.0)
      return true
    end

    # Used to contruct the dialog box which will have its body contents
    # replaced at each step.

    def build_dialog
      dialog = Gtk::Dialog.new(
        "Initial Setup",
        nil,
        Gtk::Dialog::MODAL | Gtk::Dialog::NO_SEPARATOR,
        [Gtk::Stock::CANCEL, Gtk::Dialog::RESPONSE_REJECT]
      )

      dialog.default_response = Gtk::Dialog::RESPONSE_ACCEPT

      table = Gtk::Table.new(2, 2, false)
      table.border_width = 0

      bgcolour = dialog.style.bg(Gtk::STATE_SELECTED)

      table.attach(
        Gtk::EventBox.new.modify_bg(Gtk::STATE_NORMAL, bgcolour).add(wizard_icon),
        0, 1, 0, 1, Gtk::FILL, Gtk::FILL, 0, 0
      )

      title = '<span size="xx-large" weight="heavy" foreground="white">' +
              ' SSH Menu: Initial Setup</span>'
      table.attach(
        Gtk::EventBox.new.modify_bg(Gtk::STATE_NORMAL, bgcolour).add(
          Gtk::Label.new(title).set_use_markup(true).set_width_chars(48).set_xalign(0)
        ),
        1, 2, 0, 1, Gtk::EXPAND|Gtk::FILL, Gtk::FILL, 0, 0
      )

      table.attach(
        Gtk::EventBox.new.modify_bg(Gtk::STATE_NORMAL, bgcolour).add(
          Gtk::Label.new("\n\n\n\n\n\n\n\n\n\n")
        ),
        0, 1, 1, 2, Gtk::FILL, Gtk::EXPAND|Gtk::FILL, 0, 0
      )

      @body = Gtk::Frame.new.set_shadow_type(Gtk::SHADOW_NONE)
      table.attach(@body, 1, 2, 1, 2, Gtk::FILL, 0, 20, 20)

      dialog.vbox.add(table)

      dialog.show_all

      return dialog
    end

    # Returns a Gtk::Image being the SSHMenu logo.

    def wizard_icon
      loader = Gdk::PixbufLoader.new
      loader.write(Base64.decode64(<<EOF
iVBORw0KGgoAAAANSUhEUgAAAEQAAABACAMAAACUXCGWAAAAw1BMVEXIAAAcHhslKCUrLSoyNTI3
ODA4Ozg7OzQ/QD47Qz9DQTpDREJISkdMSj1LSkNRUEhQUk9VUkVRWVVWWFVbWExZWVFeYF1aYl5h
YFhjYFNhaWVqZ1pmaGVpaGBwb2dzb2JucG17dmN3dm51d3R7d2p8fnuAf3eHg3aJhHGGh4SJiICN
j4yRkIeWk4WYmI+dn5yloZOjoZmuqpytq6OqrKmzsam6ubHEw7vOzcXY187W2NXe3dTd39zo6ebv
8e79//sAAQCpFywPAAAAAXRSTlMAQObYZgAAAAFiS0dEAIgFHUgAAAAJcEhZcwAAC4cAAAuHAZNA
h1MAAAAHdElNRQfVDAsBLCiRkORfAAAC1klEQVRYw+3WbVOiUBTA8ZV7QwrUuxCIBSyB0opIGYLG
atzv/6n2HASz2uH6olc7/mf02kz8PDwM8uPHpUuXviF+Zp3Gfv/2sX3TrnzdbrebzaYoijxLuhT+
9or9OQn/3rbb53mWrVarNBIjn4ja2B5myGsjDUQI/vOxHMuyw/enSRLHUZSegRSig5qliRDJua5b
4/Gd49zd1W9jzNB1xjRVkSnPk8QTI9r80AwKw9D3fQeyIMMwCM+SuBvZbwEZz1qiMVoEDEZ5FguR
bcbZrC38Mggj/CWOXDFihe/EJwMneY7OQfRmY7/dk4NhGQwiiNjdyGaz4o4fWnAmVM2wLKYqiqIZ
TFGYocmyxq4ACc5AdN9Xn3ZVVS4UpVlptVOYXJUyThIEZieyK+pJ/HW19sOiWrerVJVUI1VJ4Jgs
A68bKYsi5brjlBWVCFmEzToDpEd6iEh86YmQHBC4Tn3YifWCSc1KpKquJBpM4rojAZInOAml1ny9
r+ZSs/aqnazKiJAzkAxuOLblzJ8Iha8vYSUS7gtsr0jNJLbdjWyzLOa6ZT1VBR7dJ1wdWBFR8cBq
En+07WE3slrFfGxZ8qI+tZQ2K8GzQ+s3QEwBkq4izvAakymVVVavVNFUSlVNgU8qTGIKkE26jPjY
OIkd0jAVoojcdCJFArc+zfjYBwUmGY26EbhrBdz8ShwNhfCpEIkfPX7N2Md9ORC1oUiADPudSIYI
+9yJgchQhESPLleuIfVaVeCFH2U8QwSvOknq9fjDcNCNrKZTW/ST8TAQIOl0unw59nxoWff4u0mM
/DrtHppMJubt7e1PbNDWjSRfiUlLIGJ67kiM3J80aYh3YxAMBjdCJH4n3H8YsHkf37svNnc4OjbE
btr62FVTnwset0IvCKJoHs8XWP2DGkWzMPA8z3GxG8HjFjLWEKYxTdt1fNgONrJt2zRxsGYmwr/l
0e/ygHzp0v/WX7AH3cFL3lx/AAAAAElFTkSuQmCC
EOF
))
    loader.close
    return Gtk::Image.new(loader.pixbuf)
  end

    # Reads the known hosts file, skipping hashed host entries and collecting
    # hostnames from the remaining entries - returns a list of hostnames.

    def list_host_aliases
      hosts = {}
      @known_hosts_file.each_line do |line|
        if line =~ /^[|]\d+[|]/
          @hashed_hosts_skipped += 1
        elsif line =~ /^([^|]\S*)\s+ssh-\S+\s+(\S+)/
          aliases, key = $1, $2
          hosts[key] ||= []
          aliases.split(/,/).each { |h| hosts[key] << h }
        end
      end

      return hosts.values
    end

    # Given a list of aliases for the same host, returns the 'best' one.
    # The shortest alias which is not an IP address is preferred.  Otherwise,
    # IP addresses are looked up via DNS and the fully qualified domain name of
    # the first one to successfully resolve is returned.

    def best_alias(aliases)

      numeric_addr = /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/

      # Return shortest host or domain name if there is one
      names = aliases.find_all { |h| !h.match(numeric_addr) }
      return names.sort { |a,b| a.length <=> b.length }[0] if names.length > 0

      # Otherwise, try and resolve an address to a name
      aliases.each do |a|
        begin
          return canonical_name(a)
        rescue
          # Ignore it and try the next one
        end
      end

      return aliases[0]
    end

    # Given a list of addresses, returns the FQDN of the first one to resolve
    # or if none resolve, returns the last name from the list (on the assumption
    # it was added most recently).

    def best_address(*aliases)

      # Return the first one that successfully resolves
      aliases.each do |a|
        begin
          return a if canonical_name(a)
        rescue
          # Ignore it and try the next one
        end
      end

      return aliases[-1]
    end

    # Given an address, returns the fully qualified domain name.  May raise a
    # 'host not found' exception

    def canonical_name(addr)
      inet = Socket.gethostbyname(addr)
      info = Socket.gethostbyaddr(inet[3])
      return info[0]
    end

  end

end
