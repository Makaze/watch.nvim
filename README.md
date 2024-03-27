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

You can use the lua API or call the commands from the commandline. To watch the command `tree -cdC` every 500 milliseconds:

### Using the lua api

##### Start

```lua
local watch = require("watch")
watch.start("tree -cdC", 500)
```

##### Stop

```lua
local watch = require("watch")
watch.stop()
```

### Using Ex commands

##### Start

```vim
:WatchStart tree -cdC 500
```

##### Stop

```vim
:WatchStop
```

# Documentation

For examples and technical documentation about commands and the Lua API see `:help watch`.
