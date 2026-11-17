from pathlib import Path

app = Path(defines["app"])
format = "UDZO"
filesystem = "HFS+"
files = [str(app)]
symlinks = {"Applications": "/Applications"}
background = defines["background"]
# Reserve space for Finder chrome, which can follow the user's global preferences.
window_rect = ((180, 180), (640, 552))
default_view = "icon-view"
icon_size = 112
text_size = 14
icon_locations = {app.name: (160, 214), "Applications": (480, 214)}
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
icon_file = app / "Contents/Resources/AppIcon.icns"
if icon_file.exists():
    icon = str(icon_file)
