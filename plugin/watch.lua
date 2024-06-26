--- Defines a user Ex (:) command.
---
--- @param name string The name of the function. Will be called with `:{name}`.
--- @param callback function
--- @param nargs string? How many arguments. Default "*" (0 or more).
local function command(name, callback, nargs)
    vim.api.nvim_create_user_command(name, callback, { nargs = nargs or "*" })
end

--- Starts a new watcher.
---
--- @param cmd table The watched command. Refresh rate is the last argument given in milliseconds, or defaults to config if not a number.
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

--- Starts a new watcher for the currently open file. Behaves like a normal watcher, but only runs the command if the file has been modified.
---
--- @param cmd table The watched command. Use `%s` inside the command to insert the absolute path of the current file. Refresh rate is the last argument given in milliseconds, or defaults to config if not a number (minimum 1000 for file watchers).
command("WatchFile", function(cmd)
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

    local cmd_string = table.concat(new_cmd, " ")

    local file = vim.fn.expand("%:p")

    require("watch").start(cmd_string, refresh_rate, nil, file)
end, "+")

--- Stops a watcher.
---
--- `WARNING:` If `watch.config.close_on_stop` is set to `true`, then affected buffers will also be deleted.
---
--- @param cmd table The command to stop watching. If no argument is passed, defaults to current buffer if it is a watcher; prompts to stop all watchers otherwise.
command("WatchStop", function(cmd)
    local args = cmd.fargs

    if not cmd or not args or #args < 1 then
        require("watch").stop()
        return
    end

    require("watch").stop({ file = table.concat(args, " ") })
end, "*")
