require 'gnome-sshmenu'

module GnomeSSHMenuTest

  class Factory <GnomeSSHMenu::Factory

    def Factory.make_app(app_win=nil, conf_class=GnomeSSHMenuTest::Config)
      super(app_win, conf_class);
    end

    def Factory.inject_defaults
        mapper.inject('app' => GnomeSSHMenuTest::App)
    end

  end

  class App <GnomeSSHMenu::App

    def build_ui
      # Don't build a UI
    end

    def self.alert(message, detail = nil)
      puts message
      puts detail if detail
    end

  end

  class Config <GnomeSSHMenu::Config

    def load_classes
      # Don't bother reading $HOME/.sshmenu
    end

  end

end
