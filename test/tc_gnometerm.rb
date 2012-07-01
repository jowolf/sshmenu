require 'test/lib/gnome-sshmenutest.rb'

require 'test/unit'

class TC_GnomeTerm < Test::Unit::TestCase

  def setup
    GnomeSSHMenuTest::Factory.mapper.reset_mappings
    @app   = GnomeSSHMenuTest::Factory.make_app()
    @items = @app.config.set_items_from_array([
      {
        'type'        => 'host',
        'title'       => 'Example',
        'sshparams'   => '-Ax bob@example.com',
        'geometry'    => '',
        'profile'     => '',
      },
      {
        'type'        => 'menu',
        'title'       => 'Sub Menu',
        'items'       => [
          {
            'type'        => 'host',
            'title'       => 'Host A',
            'sshparams'   => 'hosta',
            'geometry'    => '',
            'profile'     => 'Prod',
          },
          {
            'type'        => 'host',
            'title'       => 'Host B',
            'sshparams'   => 'hostb',
            'geometry'    => '',
            'profile'     => '',
          },
        ],
      }
    ])
  end

  def test_window_commands
    dq = "\""
    bs = "\\"
    host = @items[0].dup

    cmnd = @app.build_window_command(host)
    assert_equal(
      "gnome-terminal " +
        "--title=#{dq}Example#{dq} " +
        "-e #{dq}sh -c #{bs}#{dq}ssh -Ax bob@example.com#{bs}#{dq}#{dq} &",
      cmnd
    )

    host.profile = "Production"
    host.title = 'The "Live" System'
    host.sshparams = 'www.example.com'
    cmnd = @app.build_window_command(host)
    assert_equal(
      "gnome-terminal " +
        "--window-with-profile=#{dq}Production#{dq} " +
        "--title=#{dq}The #{bs}#{dq}Live#{bs}#{dq} System#{dq} " +
        "-e #{dq}sh -c #{bs}#{dq}ssh www.example.com#{bs}#{dq}#{dq} &",
      cmnd
    )

    host.profile = "Big Font"
    host.title = 'Server (utf8)'
    host.sshparams = 'LANG="pl_PL.utf8" host.pl'
    cmnd = @app.build_window_command(host)
    assert_equal(
      "LANG=#{dq}pl_PL.utf8#{dq} gnome-terminal " +
        "--disable-factory " +
        "--window-with-profile=#{dq}Big Font#{dq} " +
        "--title=#{dq}Server (utf8)#{dq} " +
        "-e #{dq}sh -c #{bs}#{dq}ssh host.pl#{bs}#{dq}#{dq} &",
      cmnd
    )

    host.profile = ''
    host.sshparams = 'LANG="pl_PL.utf8" TERM="xterm-color" host.pl'
    cmnd = @app.build_window_command(host)
    assert_equal(
      "LANG=#{dq}pl_PL.utf8#{dq} TERM=#{dq}xterm-color#{dq} gnome-terminal " +
        "--disable-factory " +
        "--title=#{dq}Server (utf8)#{dq} " +
        "-e #{dq}sh -c #{bs}#{dq}ssh host.pl#{bs}#{dq}#{dq} &",
      cmnd
    )

    host.profile = 'Red'
    host.title = ''
    host.geometry = '80x24+200-0'
    host.sshparams = 'TERM="xterm-color" host.pl'
    cmnd = @app.build_window_command(host)
    assert_equal(
      "TERM=#{dq}xterm-color#{dq} gnome-terminal " +
        "--disable-factory " +
        "--geometry=80x24+200-0 " +
        "--window-with-profile=#{dq}Red#{dq} " +
        "--title=#{dq}#{dq} " +
        "-e #{dq}sh -c #{bs}#{dq}ssh host.pl#{bs}#{dq}#{dq} &",
      cmnd
    )

    host.profile = ''
    host.title = ''
    host.geometry = '80x24+200-0'
    host.sshparams = 'TERM="xterm-color" host.pl'
    cmnd = @app.build_window_command(host)
    assert_equal(
      "TERM=#{dq}xterm-color#{dq} gnome-terminal " +
        "--disable-factory " +
        "--geometry=80x24+200-0 " +
        "--title=#{dq}#{dq} " +
        "-e #{dq}sh -c #{bs}#{dq}ssh host.pl#{bs}#{dq}#{dq} &",
      cmnd
    )

    host.title = 'Logged Session'
    host.geometry = ''
    host.sshparams = 'root@fw | tee /var/log/fw_session.log'
    cmnd = @app.build_window_command(host)
    assert_equal(
      "gnome-terminal " +
        "--title=#{dq}Logged Session#{dq} " +
        "-e #{dq}sh -c #{bs}#{dq}ssh root@fw | tee /var/log/fw_session.log#{bs}#{dq}#{dq} &",
      cmnd
    )

    host.title = 'Logged Session'
    host.geometry = ''
    host.sshparams = "root@fw | tee /var/log/fw_session-`date +'%F-%T'`.log"
    cmnd = @app.build_window_command(host)
    assert_equal(
      "gnome-terminal " +
        "--title=#{dq}Logged Session#{dq} " +
        "-e #{dq}sh -c #{bs}#{dq}ssh root@fw | tee " +
        "/var/log/fw_session-#{bs}#{bs}#{bs}`date +'%F-%T'#{bs}#{bs}#{bs}`" +
        ".log#{bs}#{dq}#{dq} &",
      cmnd
    )

    host.title = 'No Menu'
    host.geometry = '120x30+0-0 --hide-menubar'
    host.sshparams = "hostc"
    cmnd = @app.build_window_command(host)
    assert_equal(
      "gnome-terminal " +
        "--geometry=120x30+0-0 --hide-menubar " +
        "--title=#{dq}No Menu#{dq} " +
        "-e #{dq}sh -c #{bs}#{dq}ssh hostc#{bs}#{dq}#{dq} &",
      cmnd
    )

  end

  def test_tabbed_window_commands
    dq = "\""
    bs = "\\"
    menu = @items[1].dup

    cmnd = @app.build_tabbed_window_command(menu)
    assert_equal(
      "gnome-terminal " +
        "--tab-with-profile=#{dq}Prod#{dq} " +
        "--title=#{dq}Host A#{dq} " +
        "-e #{dq}sh -c #{bs}#{dq}ssh hosta#{bs}#{dq}#{dq} " +
        "--tab-with-profile=Default " +
        "--title=#{dq}Host B#{dq} " +
        "-e #{dq}sh -c #{bs}#{dq}ssh hostb#{bs}#{dq}#{dq} &",
      cmnd
    )

    menu.items[0].geometry = '132x24'
    menu.items[0].profile  = ''
    menu.items[1].profile  = 'Dev'
    cmnd = @app.build_tabbed_window_command(menu)
    assert_equal(
      "gnome-terminal " +
        "--geometry=132x24 " + 
        "--tab-with-profile=Default " +
        "--title=#{dq}Host A#{dq} " +
        "-e #{dq}sh -c #{bs}#{dq}ssh hosta#{bs}#{dq}#{dq} " +
        "--tab-with-profile=#{dq}Dev#{dq} " +
        "--title=#{dq}Host B#{dq} " +
        "-e #{dq}sh -c #{bs}#{dq}ssh hostb#{bs}#{dq}#{dq} &",
      cmnd
    )

    menu.items[1].geometry = '40x16'
    menu.items[1].profile  = ''
    cmnd = @app.build_tabbed_window_command(menu)
    assert_equal(
      "gnome-terminal " +
        "--geometry=132x24 " + 
        "--tab-with-profile=Default " +
        "--title=#{dq}Host A#{dq} " +
        "-e #{dq}sh -c #{bs}#{dq}ssh hosta#{bs}#{dq}#{dq} " +
        "--tab-with-profile=Default " +
        "--title=#{dq}Host B#{dq} " +
        "-e #{dq}sh -c #{bs}#{dq}ssh hostb#{bs}#{dq}#{dq} &",
      cmnd
    )

    menu.items[0].sshparams = 'LANG="fr_CA.utf8" hosta'
    menu.items[1].profile  = ''
    cmnd = @app.build_tabbed_window_command(menu)
    assert_equal(
      "LANG=#{dq}fr_CA.utf8#{dq} gnome-terminal " +
        "--disable-factory "+
        "--geometry=132x24 " + 
        "--tab-with-profile=Default " +
        "--title=#{dq}Host A#{dq} " +
        "-e #{dq}sh -c #{bs}#{dq}ssh hosta#{bs}#{dq}#{dq} " +
        "--tab-with-profile=Default " +
        "--title=#{dq}Host B#{dq} " +
        "-e #{dq}sh -c #{bs}#{dq}ssh hostb#{bs}#{dq}#{dq} &",
      cmnd
    )

    menu.items[1].sshparams = 'LANG="en_UK.iso8859-1" hostb'
    cmnd = @app.build_tabbed_window_command(menu)
    assert_equal(
      "LANG=#{dq}fr_CA.utf8#{dq} gnome-terminal " +
        "--disable-factory "+
        "--geometry=132x24 " + 
        "--tab-with-profile=Default " +
        "--title=#{dq}Host A#{dq} " +
        "-e #{dq}sh -c #{bs}#{dq}ssh hosta#{bs}#{dq}#{dq} " +
        "--tab-with-profile=Default " +
        "--title=#{dq}Host B#{dq} " +
        "-e #{dq}sh -c #{bs}#{dq}ssh hostb#{bs}#{dq}#{dq} &",
      cmnd
    )

    menu.items[0].sshparams = 'hosta | tee -a $HOME/hosta.log'
    menu.items[0].geometry  = ''
    cmnd = @app.build_tabbed_window_command(menu)
    assert_equal(
      "gnome-terminal " +
        "--tab-with-profile=Default " +
        "--title=#{dq}Host A#{dq} " +
        "-e #{dq}sh -c #{bs}#{dq}ssh hosta | " +
          "tee -a #{bs}#{bs}#{bs}$HOME/hosta.log#{bs}#{dq}#{dq} " +
        "--tab-with-profile=Default " +
        "--title=#{dq}Host B#{dq} " +
        "-e #{dq}sh -c #{bs}#{dq}ssh hostb#{bs}#{dq}#{dq} &",
      cmnd
    )

    menu.items[0].enable_bcvi = true
    cmnd = @app.build_tabbed_window_command(menu)
    assert_equal(
      "gnome-terminal " +
        "--tab-with-profile=Default " +
        "--title=#{dq}Host A#{dq} " +
        "-e #{dq}sh -c #{bs}#{dq}bcvi --wrap-ssh -- hosta | " +
          "tee -a #{bs}#{bs}#{bs}$HOME/hosta.log#{bs}#{dq}#{dq} " +
        "--tab-with-profile=Default " +
        "--title=#{dq}Host B#{dq} " +
        "-e #{dq}sh -c #{bs}#{dq}ssh hostb#{bs}#{dq}#{dq} &",
      cmnd
    )

  end

end
