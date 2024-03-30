--- Defines a user Ex command.
---
--- @param name string The name of the function. Will be called with `:{name}`
--- @param callback function
--- @param nargs string? How many arguments. Default "*" (0 or more)
local function command(name, callback, nargs)
    vim.api.nvim_create_user_command(name, callback, { nargs = nargs or "*" })
end

--- Starts a new watcher.
---
--- @param cmd table The watched command. Final argument is the refresh rate
---                  in milliseconds, or nil if not a number
command("WatchStart", function(cmd)
    local args = cmd.fargs

    -- Add the last argument to command if not a number
    local refresh_rate = tonumber(args[#args])
    local from = 1
    local to = refresh_rate and #args - 1 or #args

    -- Get the command(s) from the arguments
    local new_cmd = {}
    for i = from, to do
        table.insert(new_cmd, args[i])
    end

    require("watch").start(table.concat(new_cmd, " "), refresh_rate, nil)
end, "+")

--- Stops a watcher.
---
--- @param cmd table The command to stop watching. Default all if empty.
command("WatchStop", function(cmd)
    local args = cmd.fargs

    if not cmd or not args or #args < 1 then
        require("watch").stop()
        return
    end

    require("watch").stop({ file = table.concat(args, " ") })
end, "*")
