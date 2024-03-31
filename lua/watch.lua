--- @class watch.Watcher
---
--- @field command string The command to watch. Serves as the name of the watcher.
--- @field refresh_rate integer The refresh rate for the watcher in milliseconds.
--- @field bufnr integer The buffer number attached to the watcher.
--- @field timer function The timer object attached to the watcher.

local Watch = {}

local A = vim.api
local uv = vim.uv or vim.loop
local input = require("watch.input")

--- Checks if a buffer is visible.
---
--- @param bufnr integer The buffer number to check
--- @return boolean visible
local function is_visible(bufnr)
    return vim.iter(A.nvim_list_wins()):any(function(win)
        return A.nvim_win_get_buf(win) == bufnr
    end)
end

--- Removes the current working directory from a buffer name.
---
--- @param name string Expanded buffer name.
--- @return string collapsed_name
local function collapse_bufname(name)
    local cwd = uv.cwd()
    name = name:gsub(cwd .. "/", "")
    name = name:gsub(cwd .. "\\", "")
    return name
end

--- Gets the buffer number by the buffer name. Returns `nil` if not found.
---
--- @param name string The buffer name to get.
--- @return integer|nil bufnr
local function get_buf_by_name(name)
    return vim.iter(A.nvim_list_bufs()):find(function(b)
        local bufname = collapse_bufname(A.nvim_buf_get_name(b))
        return bufname == name
    end)
end

--- @type watch.Watcher[]
---
--- Global list of watchers and associated data.
Watch.watchers = {}

--- @class watch.Config
---
--- @field refresh_rate integer The default refresh rate for a new watcher in milliseconds. Defaults to `500`.
--- @field close_on_stop boolean Whether to automatically delete the buffer when stopping a watcher. Defaults to `false`.
---
--- Configuration for watch.nvim.

--- @type watch.Config
Watch.config = {
    refresh_rate = 500,
    close_on_stop = false,
}

--- @class watch.ConfigOverride
---
--- @field refresh_rate integer? The default refresh rate for a new watcher in milliseconds. Defaults to `500`.
--- @field close_on_stop boolean? Whether to automatically delete the buffer when stopping a watcher. Defaults to `false`.
---
--- Configuration overrides for watch.nvim.

--- Changes configuration options. See `:help watch-config`.
--- You do not have to call this function unless you want to change anything!
---
--- @param opts watch.ConfigOverride?
Watch.setup = function(opts)
    -- Do nothing if nothing given
    if not opts or not next(opts) then
        return
    end
    Watch.config =
        vim.tbl_deep_extend("force", Watch.config, vim.F.if_nil(opts, {}))
end

--- Replaces a buffer's contents with a shell command while preserving the cursor.
---
--- @param command string Shell command.
--- @param bufnr integer The buffer number to update.
--- @return function updater Steps to take upon rerunning `command`.
Watch.update = function(command, bufnr)
    return function()
        -- Do nothing if not visible
        if not is_visible(bufnr) then
            return
        end

        -- Execute your command and capture its output
        -- Use vim.system for async
        local code = vim.system(
            vim.split(command, " "),
            { text = true },
            function(out)
                -- Need vim.schedule to use most actions inside of vim loop
                vim.schedule(function()
                    -- Handle error
                    if out.code ~= 0 then
                        Watch.stop(command)
                        vim.notify(
                            "[watch] ! Stopping: " .. out.stderr,
                            vim.log.levels.ERROR
                        )
                        return
                    end

                    -- Save current cursor position
                    local save_cursor = A.nvim_win_get_cursor(0)

                    local output = vim.split(out.stdout, "\n")

                    -- Strip ANSI color codes from the output
                    local stripped_output = {}
                    for _, line in ipairs(output) do
                        local stripped_line = line:gsub("\27%[[%d;]*[mK]", "") -- Remove ANSI escape sequences
                        table.insert(stripped_output, stripped_line)
                        -- table.insert(stripped_output, line)
                    end

                    -- Clear the buffer and insert the stripped output
                    A.nvim_buf_set_lines(bufnr, 0, -1, false, stripped_output)

                    -- Restore cursor position
                    A.nvim_win_set_cursor(0, save_cursor)
                end)
            end
        )

        if code then
            Watch.stop(command)
        end
    end
end

--- Starts continually reloading a buffer's contents with a shell command. If the command is aleady being watched, then opens that buffer in the current window.
---
--- @param command string Shell command.
--- @param refresh_rate integer? Time between reloads in milliseconds. Defaults to `watch.config.refresh_rate`.
--- @param bufnr integer? Buffer number to update. Defaults to a new buffer.
Watch.start = function(command, refresh_rate, bufnr)
    -- Check if command is nil
    if not command or not string.len(command) then
        vim.notify("[watch] Error: Empty command passed", vim.log.levels.ERROR)
        return
    end

    -- Check if command is a valid executable
    if vim.fn.executable(vim.split(command, " ")[1]) ~= 1 then
        vim.notify(
            "[watch] Error: Not a valid executable",
            vim.log.levels.ERROR
        )
        return
    end

    -- Open the buffer if already running
    if Watch.watchers[command] then
        bufnr = Watch.watchers[command].bufnr
        vim.notify(
            "[watch] "
                .. command
                .. " was already being watched on bufnr="
                .. bufnr
                .. ". Switching..."
        )
        A.nvim_win_set_buf(0, bufnr)
        return
    end

    -- Default to config refresh setting
    if not refresh_rate or refresh_rate <= 0 then
        refresh_rate = Watch.config.refresh_rate
    end

    -- Get existing bufnr if bufname already exists
    bufnr = get_buf_by_name(command) or bufnr

    -- Create a new buffer if not
    if not bufnr then
        bufnr = A.nvim_create_buf(true, true)
        A.nvim_set_option_value("buftype", "nofile", { buf = bufnr })
        A.nvim_buf_set_name(bufnr, command)
        A.nvim_win_set_buf(0, bufnr)
    end

    -- Set up a timer to run the function every refresh_rate
    local timer = uv.new_timer()
    timer:start(
        0,
        refresh_rate,
        vim.schedule_wrap(Watch.update(command, bufnr))
    )

    --- @type watch.Watcher
    local watcher = {
        command = command,
        bufnr = bufnr,
        refresh_rate = refresh_rate,
        timer = timer,
    }

    Watch.watchers[command] = watcher

    local group = A.nvim_create_augroup("WatchCleanUp", { clear = true })

    -- Stop the timer when the buffer is unloaded or when quitting Neovim
    A.nvim_create_autocmd({ "BufUnload", "VimLeavePre" }, {
        group = group,
        buffer = bufnr,
        callback = Watch.stop,
    })
end

--- Stops watching the specified command and detaches from the buffer. If no argument is given, then checks the current buffer. If the current buffer is also not attached to a watcher, then prompts the user before stopping all of them.
---
--- `WARNING:` If `watch.config.close_on_stop` is set to `true`, then affected buffers will also be deleted.
---
--- @param event string|table? The command name to stop. If string, then uses the string. If table, then uses `event.file`.
Watch.stop = function(event)
    -- Get the current buffer if it is a watcher
    local bufname = nil
    -- Count keys the hard way
    local watch_count = 0
    for _ in pairs(Watch.watchers) do
        watch_count = watch_count + 1
    end
    if not event or not event.event then
        bufname = collapse_bufname(vim.fn.expand("%"))
        event = Watch.watchers[bufname] and bufname or nil
        -- Prompt if they want to close all buffers
        if not event then
            local response = vim.notify(
                "Not a watch buffer. Stop all ("
                    .. watch_count
                    .. ") watchers (y/n)? ",
                vim.log.levels.WARN
            )
            response = input.get_char()
            if response ~= "y" and response ~= "Y" then
                return
            end
        end
    end
    if not event or event.event == "VimLeavePre" then
        for command, W in pairs(Watch.watchers) do
            W.timer:stop()
            W.timer:close()
            Watch.watchers[command] = nil
            if Watch.config.close_on_stop then
                vim.schedule(function()
                    A.nvim_buf_delete(W.bufnr, { force = true })
                end)
            end
        end
        vim.notify("[watch] Stopped " .. watch_count .. " watchers")
    else
        local command = event or event.file
        local W = Watch.watchers[command]
        -- Only error when not expected
        if not W then
            if not event or not event.event or event.event ~= "BufUnload" then
                vim.notify(
                    "[watch] Error: Already not watching " .. command,
                    vim.log.levels.WARN
                )
            end

            return
        end
        W.timer:stop()
        W.timer:close()
        Watch.watchers[command] = nil
        if Watch.config.close_on_stop then
            vim.schedule(function()
                A.nvim_buf_delete(W.bufnr, { force = true })
            end)
        end
        vim.notify("[watch] Stopped watching " .. command)
    end
end

return Watch
