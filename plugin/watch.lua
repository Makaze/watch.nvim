--- Define a user command
---
--- @param name string The name of the function. Will be called with `:{name}`
--- @param callback function
--- @param nargs string? How many arguments. Default "*" (0 or more)
local function command(name, callback, nargs)
    vim.api.nvim_create_user_command(name, callback, { nargs = nargs or "*" })
end

--- Start a new watcher
---
--- @param args string[] The watched command. Final argument is the refresh rate
---                      in milliseconds, or nil if not a number
command("WatchStart", function(args)
    -- First value is the name of the command
    local from = 2

    -- Add the last argument to command if not a number
    local refresh_rate = tonumber(args[#args])
    local to = refresh_rate and #args - 1 or #args

    -- Get the command(s) from the arguments
    local cmd = {}
    for i = from, to do
        table.insert(cmd, args[i])
    end

    require("watch").start(table.concat(cmd, " "), refresh_rate)
end, "+")

--- Stop all watchers
---
--- @param args string[]? The command to stop watching. Defaults to all
command("WatchStop", function(args)
    if not args or #args < 2 then
        require("watch").stop()
        return
    end

    -- First value is the name of the command
    local from = 2
    local to = #args

    -- Get the command(s) from the arguments
    local cmd = {}
    for i = from, to do
        table.insert(cmd, args[i])
    end

    require("watch").stop({ file = table.concat(cmd, " ") })
end, nil)
