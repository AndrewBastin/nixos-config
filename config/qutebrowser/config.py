import catppuccin

config.load_autoconfig()

c.content.blocking.enabled = False

c.content.javascript.alert = False

c.tabs.show = "multiple"

c.scrolling.smooth = True

c.colors.webpage.preferred_color_scheme = "dark"

catppuccin.setup(c, "frappe")
