#!/usr/bin/env python
#
# Create a full screen web browser showing the URL passed as first command line
# argument. The browser is very minimal: no menus or window chrome. A scrolling
# view is used.
#
# Requires Gtk 3 and WebKit2 4 and GObject Introspection, e.g.

import gi, signal, sys

gi.require_version('Gtk', '3.0')
gi.require_version('WebKit2', '4.0')
from gi.repository import GLib ,Gtk, WebKit2

win = Gtk.Window()
win.connect('destroy', lambda w: Gtk.main_quit())

web = WebKit2.WebView()

settings = web.get_settings()
settings.set_allow_modal_dialogs(False)
settings.set_enable_plugins(False)
settings.set_enable_java(False)
settings.set_enable_write_console_messages_to_stdout(True)

web.get_context().set_cache_model(WebKit2.CacheModel.DOCUMENT_BROWSER)

scroller = Gtk.ScrolledWindow()
scroller.add(web)
win.add(scroller)

web.load_uri(sys.argv[1])

win.fullscreen()
win.show_all()

GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, Gtk.main_quit)

Gtk.main()
