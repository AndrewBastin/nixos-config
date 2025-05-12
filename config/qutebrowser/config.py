import catppuccin

config.load_autoconfig()

c.content.blocking.enabled = False

c.content.javascript.alert = False

c.tabs.show = "multiple"

catppuccin.setup(c, "frappe")
