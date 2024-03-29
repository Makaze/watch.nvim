# watch.nvim

A scrollable `watch` alternative for Neovim.

> [!IMPORTANT]
> `watch.nvim` requires Neovim 0.10+!

`watch.nvim` is a simple plugin for watching the live output of a shell command
in a Neovim buffer. 

### Use case:

1. You want to `watch` (continuously rerun and check the output) a command with
   changing output, while being able to scroll the output, all without leaving
   Neovim.
2. You `watch.start()` or `:WatchStart` a shell command.
3. The command's output is continuously loaded in a buffer at the given refresh
   rate.
4. The watcher stops when you call `watch.stop()` or `:WatchStop`, close the
   buffer, or exit Neovim.

For an example, to watch the output of `tree -cdC` in the current directory,
updating every `500` ms:

```vim
:WatchStart tree -cdC 500
```

Keep in mind that a call to watched command will run in the shell where you
started Neovim.

##### Features:
[*] Custom refresh rate
[*] Scrollable
[*] Pause watching in the background

##### Planned:
[ ] ANSI color support

# Quickstart

Install using your favorite plugin manager.

Using [lazy.nvim](https://github.com/nvim-telescope/telescope.nvim):

```lua
{
    "Makaze/watch.nvim",
    cmd = { "WatchStart", "WatchStop" },
}
```

> [!NOTE]
> Calling `.setup()` is not required.

# Configuration

`watch.nvim` has two configuration options. Any ommitted options will default to the standard configuration below. You can change those options by calling `watch.setup()`:

```lua
local watch = require("watch")

watch.setup({
    -------------------- Default configuration -----------------------------
    refresh_rate = 500,     -- The default refresh rate for a new watcher in
                            -- milliseconds. Defaults to `500`.
    close_on_stop = false,  -- Whether to automatically delete the buffer
                            -- when stopping a watcher. Defaults to `false`.
})
```

# Example Usage

You can use the Lua API or call the commands from the commandline. To watch the command `tree -cdC` every 500 milliseconds:

### Lua API

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

### Ex Commands

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
