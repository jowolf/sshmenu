BIN   = $(DESTDIR)/usr/bin
LIB   = $(DESTDIR)/usr/lib
MAN   = $(DESTDIR)/usr/share/man
SHARE = $(DESTDIR)/usr/share
CFG   = $(DESTDIR)/etc

all: lib/sshmenu.rb

clean:

TEST:
	RUBYLIB=lib ruby test/ts_all.rb test/tc*.rb

install:
	install -d $(BIN) $(LIB)/ruby/1.8 $(LIB)/bonobo/servers
	install -d $(LIB)/gnome-panel $(SHARE)/icons/hicolor/48x48/apps
	install -d $(MAN)/man1
	install -d $(CFG)/bash_completion.d
	install -m644 lib/sshmenu.rb $(LIB)/ruby/1.8/sshmenu.rb
	install -m644 lib/gnome-sshmenu.rb $(LIB)/ruby/1.8/gnome-sshmenu.rb
	install -m644 sshmenu-applet.server $(LIB)/bonobo/servers/sshmenu-applet.server
	install -m755 sshmenu-applet $(LIB)/gnome-panel/sshmenu-applet
	install -m644 sshmenu.1 $(MAN)/man1/sshmenu.1
	install -m644 gnome-sshmenu-applet.png $(SHARE)/icons/hicolor/48x48/apps/gnome-sshmenu-applet.png
	install -m755 bin/sshmenu $(BIN)/sshmenu
	install -m755 bin/sshmenu-gnome $(BIN)/sshmenu-gnome
	install -m644 bash/sshmenu $(CFG)/bash_completion.d/sshmenu

deb:
	#fakeroot ./debian/rules binary
	dpkg-buildpackage -rfakeroot
