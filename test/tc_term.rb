require 'test/unit'
require 'test/lib/sshmenutest.rb'

class TC_Term < Test::Unit::TestCase

  def setup
    SSHMenuTest::Factory.mapper.reset_mappings
    @app   = SSHMenuTest::Factory.make_app()
    @items = @app.config.set_items_from_array([
      {
        'type'        => 'host',
        'title'       => 'Example',
        'sshparams'   => '-Ax bob@example.com',
        'geometry'    => '',
      }
    ])
  end

  def test_quoting
    s = @app.shell_quote('echo')
    assert_equal('"echo"', s)

    dq = "\""
    bs = "\\"
    bt = "`"
    s = @app.shell_quote("echo 'Hello World'")
    assert_equal("#{dq}echo 'Hello World'#{dq}", s)

    s = @app.shell_quote('echo "Hello World"')
    assert_equal("#{dq}echo #{bs}#{dq}Hello World#{bs}#{dq}#{dq}", s)

    s = @app.shell_quote('sh -c "echo \"Hello World\""')
    assert_equal("#{dq}sh -c #{bs}#{dq}echo #{bs}#{bs}#{bs}#{dq}Hello World#{bs}#{bs}#{bs}#{dq}#{bs}#{dq}#{dq}", s)

    s = @app.shell_quote("echo `pwd`")
    assert_equal("#{dq}echo #{bs}#{bt}pwd#{bs}#{bt}#{dq}", s)
  end

  def test_window_commands
    dq = "\""
    bs = "\\"
    host = @items[0].dup
    cmnd = @app.build_window_command(host)
    assert_equal(
      "xterm -T #{dq}Example#{dq} -e sh -c #{dq}ssh -Ax bob@example.com#{dq} &",
      cmnd
    )

    host.sshparams = 'LANG="pl_PL.utf8" kate@example.pl'
    cmnd = @app.build_window_command(host)
    assert_equal(
      "LANG=#{dq}pl_PL.utf8#{dq} xterm -T #{dq}Example#{dq} -e sh -c " +
        "#{dq}ssh kate@example.pl#{dq} &",
      cmnd
    )

    host.sshparams = 'LANG="pl_PL.utf8" TERM="xterm-color" kate@example.pl'
    cmnd = @app.build_window_command(host)
    assert_equal(
      "LANG=#{dq}pl_PL.utf8#{dq} TERM=#{dq}xterm-color#{dq} xterm -T " +
        "#{dq}Example#{dq} -e sh -c #{dq}ssh kate@example.pl#{dq} &",
      cmnd
    )

    host.title = 'The "Live" Server'
    host.sshparams = 'www.example.com'
    host.enable_bcvi = true
    cmnd = @app.build_window_command(host)
    assert_equal(
      "xterm -T #{dq}The #{bs}#{dq}Live#{bs}#{dq} Server#{dq} -e sh -c " +
        "#{dq}bcvi --wrap-ssh -- www.example.com#{dq} &",
      cmnd
    )

    host.title = 'Web Server'
    host.sshparams = 'www.example.com'
    host.enable_bcvi = false
    host.geometry = '80x24+0+0'
    cmnd = @app.build_window_command(host)
    assert_equal(
      "xterm -T #{dq}Web Server#{dq} -geometry 80x24+0+0 -e sh -c " +
        "#{dq}ssh www.example.com#{dq} &",
      cmnd
    )

    host.geometry = '120x30+0-0 -bg white -fg black'
    cmnd = @app.build_window_command(host)
    assert_equal(
      "xterm -T #{dq}Web Server#{dq} " +
        "-geometry 120x30+0-0 -bg white -fg black -e sh -c " +
        "#{dq}ssh www.example.com#{dq} &",
      cmnd
    )

    host.title = 'Host A'
    host.sshparams = 'hosta | tee -a $HOME/hosta.log'
    host.geometry = ''
    cmnd = @app.build_window_command(host)
    assert_equal(
      "xterm -T #{dq}Host A#{dq} " +
        "-e sh -c #{dq}ssh hosta | tee -a #{bs}$HOME/hosta.log#{dq} &",
      cmnd
    )

  end

end
