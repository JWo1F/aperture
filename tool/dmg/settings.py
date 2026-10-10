# dmgbuild settings for the release DMG. tool/make_dmg.sh passes the staged
# app as `-D app=<path>`; everything else about the window lives here.
#
# Icon centres must match the label chips drawn in background.svg.
import os.path

app = defines["app"]  # noqa: F821 — injected by dmgbuild
app_name = os.path.basename(app)

format = "UDZO"
compression_level = 9
filesystem = "HFS+"

files = [app]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")

# dmgbuild execs this file without __file__, so the path is relative to the
# repository root, where make_dmg.sh runs it. background@2x.png beside it is
# picked up for Retina.
background = "tool/dmg/background.png"
# The frame includes the title bar. 482 shows the background's top 420pt
# even when Finder adds its status bar regardless of show_status_bar; the
# background runs to 460 so no white strip shows when it does not.
window_rect = ((200, 120), (660, 482))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 128
text_size = 12
icon_locations = {
    app_name: (180, 200),
    "Applications": (480, 200),
}
