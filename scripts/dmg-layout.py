# Mise en page de la fenêtre du DMG, lue par dmgbuild depuis scripts/make-dmg.sh.
# Les positions des icônes correspondent à la flèche dessinée par scripts/dmg-background.swift.
import os.path

app = defines["app"]

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}

background = defines["background"]
window_rect = ((200, 160), (660, 420))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 128
text_size = 13
icon_locations = {
    os.path.basename(app): (160, 190),
    "Applications": (500, 190),
}
