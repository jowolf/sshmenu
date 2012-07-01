require 'test/unit'
require 'sshmenu'

class TC_Basic < Test::Unit::TestCase

  def setup
    SSHMenu::Config.new.inject_defaults
  end

  def test_version
    assert_equal(SSHMenu.version, version_from_changes())
  end

  def test_separator_items
    sep = SSHMenu::MenuItem.new_from_hash({
      'type'  => 'separator',
      'extra' => 'cheese'
    })
    assert_equal('separator', sep.type)
    assert_equal(true,        sep.separator?)
    assert_equal(false,       sep.host?)
    assert_equal(false,       sep.menu?)

    s = sep.to_h
    assert_equal('separator', s['type'])
    assert_nil(s['extra'], 'extra hash keys are discarded')
  end

  def test_host_items
    host = SSHMenu::MenuItem.new_from_hash({
      'type'        => 'host',
      'title'       => 'Example',
      'sshparams'   => '-Ax bob@example.com',
      'geometry'    => '80x25',
      'enable_bcvi' => true,
      'extra'       => 'read all about it'
    })
    assert_equal('host',                host.type)
    assert_equal('Example',             host.title)
    assert_equal('-Ax bob@example.com', host.sshparams)
    assert_equal('80x25',               host.geometry)
    assert_equal('',                    host.env_settings)
    assert_equal('-Ax bob@example.com', host.sshparams_noenv)
    assert_equal(true,                  host.enable_bcvi)
    assert_equal(false,                 host.separator?)
    assert_equal(true,                  host.host?)
    assert_equal(false,                 host.menu?)

    h = host.to_h
    assert_equal('read all about it',   h['extra'])

    host2 = host.dup
    assert_equal('host',                host2.type)
    assert_equal('Example',             host2.title)
    assert_equal('-Ax bob@example.com', host2.sshparams)
    assert_equal('80x25',               host2.geometry)
    assert_equal(true,                  host2.enable_bcvi)

    host.title        = 'Tail Log'
    host.sshparams    = 'LC_ALL="en_GB.utf8" webserver tail -f error.log'
    host.geometry     = ''
    host.enable_bcvi  = false
    assert_equal('Tail Log',                    host.title)
    assert_equal('LC_ALL="en_GB.utf8" webserver tail -f error.log', host.sshparams)
    assert_equal('LC_ALL="en_GB.utf8" ',        host.env_settings)
    assert_equal('webserver tail -f error.log', host.sshparams_noenv)
    assert_equal(false,                         host.enable_bcvi)

    conf = { 'host' => host.to_h, 'host2' => host2.to_h }
    assert_equal('host', conf['host']['type'])
    assert_equal('host', conf['host2']['type'])
    assert_equal('Tail Log', conf['host']['title'])
    assert_equal('Example', conf['host2']['title'])
    assert_equal(true, conf['host2']['enable_bcvi'])
    assert_equal(nil,  conf['host']['enable_bcvi'])
    assert_equal('read all about it',  conf['host']['extra'])
    assert_equal('read all about it',  conf['host2']['extra'])
  end

  def test_menu_items
    menu = SSHMenu::MenuItem.new_from_hash({
      'type'        => 'menu',
      'title'       => 'Menu One',
      'items'       => [ ]
    })
    assert_equal('menu',                menu.type)
    assert_equal('Menu One',            menu.title)
    assert_equal(false,                 menu.separator?)
    assert_equal(false,                 menu.host?)
    assert_equal(true,                  menu.menu?)
    assert_equal(false,                 menu.has_children?)

    menu.append_item(
      SSHMenu::MenuItem.new_from_hash({'type'  => 'separator'})
    )
    assert_equal(true,                  menu.has_children?)

    menu.clear_items
    assert_equal(false,                 menu.has_children?)
  end

  private

    def version_from_changes
      changes = File.join( File.dirname(__FILE__), '/..', 'Changes' )
      File.open(changes).each do |line|
        if line =~ /^(\d+\.\d+)/
          return $1
        end
      end
    end

end
