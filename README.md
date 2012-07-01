sshmenu
=======

sshmenu, with newer updates for various platforms, Forked from 3.18 sshmenu on sourceforge.


Background
==========

Since the original sshmenu, at sshmenu.sourceforge.net/dev/hackers_guide.html, has been stale since about 2009, I have forked this to update it here to at least be able to use it:

Grant McLean's (the original author) stated reasoning, according to the [2011 mailing list posting](http://sourceforge.net/mailarchive/forum.php?thread_name=20111122230211.GB7568%40apollo.cpu.lublin.pl&forum_name=sshmenu-users), is:

"I'm not clear at all on what the future of applets is for GNOME 3.  I'm
still on GNOME 2 for that reason."

My take on it, is that the huge CF (ClusterFork) of the Linux Desktop, caused by the Gnome3 / Unity debacle, has cause a lot of fallout and fragmentation due to the various incompatibliilities and lack of coherent support for any way to implement Panel Applets in a consistent matter across various desktops, - And worst, not even within GFnome itself.

What were they thinking?!

The two worst things holding back Linux desktop adoption, are (1) fragmentstion (or the perception and uncertainty surrounding it), and the (2) lack of hardware / corporate support for hardware.

This whole Gnome3 / Unity train wreck sets the Linux Desktop back hugely, and gives the naysayers something to point at for why they should stick with Windows or Mac.


Anyway, my current strategy is to use the ssmenu standalone app, which launches as a small square about the size of an icon - BUT: it launched xterm by default, and this is not as nice as using the built-in terminal for the desktop in question, be it gnome-terminal, lxterminal, or whatever.

Also, there's no reason that gnome-terminal (or mate-terminal, or lxterminal, for that matter) can't be used to provide the terminal capabilities (without requiring gnome-sshmenu), I have implemeted a config option for this.



Other related projects of note:
===============================

- https://github.com/anilgulecha/misc/blob/master/sshplus.py
- https://github.com/sciancio/connectionmanager
- https://github.com/MasslessParticle/pySSHMenu


Possible Future Directions:
===========================

 - Add panel applet capabilities with other windowing systems, such as XFCE, LXDE, MATE, Cinnamon, etc.
 - Refactor more terminal launch options into the connfig file 
 - Merge functionality with the related projects mentioned above
 