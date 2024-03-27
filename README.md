# watch.nvim

A scrollable `watch` alternative for Neovim. `watch.nvim` is a simple Neovim plugin that mimics the `watch` linux command in a Neovim buffer.

> [!IMPORTANT]
> `watch.nvim` requires neovim 0.9.5+!

# Quickstart

Install using your favorite plugin manager.

Using [lazy.nvim](https://github.com/nvim-telescope/telescope.nvim):

```lua
{ "Makaze/watch.nvim" }
```

> [!NOTE]
> Calling `.setup()` is not required.

# Example usage:

You can use the Lua API or call the commands from the commandline. To watch the command `tree -cdC` every 500 milliseconds:

### Using the Lua API

##### Start

```lua
local watch = require("watch")
watch.start("tree -cdC", 1000)      -- Specify 1000 ms refresh
watch.start("tree -cdC")            -- Default to 500 ms refresh
```

##### Stop

```lua
local watch = require("watch")
watch.stop({ file = "tree -cdC" })  -- Stop watching `tree -cdC`
watch.stop()                        -- Stop all watchers
```

### Using Ex commands

##### Start

```vim
:WatchStart tree -cdC 1000          " Specify 1000 ms refresh
:WatchStart tree -cdC               " Default to 500 ms refresh
```

##### Stop

```vim
:WatchStop tree -cdC                " Stop watching `tree -cdC`
:WatchStop                          " Stop all watchers
```

# Documentation

For examples and technical documentation about commands and the Lua API see `:help watch`.
