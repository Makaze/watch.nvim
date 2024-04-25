--- @class watch.Watcher
---
--- @field command string The command to watch. Serves as the name of the watcher.
--- @field refresh_rate integer The refresh rate for the watcher in milliseconds.
--- @field bufnr integer The buffer number attached to the watcher.
--- @field timer function The timer object attached to the watcher.
--- @field file string|nil The filename to watch (if applicable).
--- @field last_updated integer The time since the file was last checked. Used when watching files.
--- @field ANSI_enabled boolean Whether ANSI color support has been applied to the watcher.

local Watch = {}

local A = vim.api
local uv = vim.uv or vim.loop
local input = require("watch.input")

--- Checks if a buffer is visible.
---
--- @param bufnr integer The buffer number to check
--- @return boolean visible
local function is_visible(bufnr)
    if vim.iter then
        return vim.iter(A.nvim_list_wins()):any(function(win)
            return A.nvim_win_get_buf(win) == bufnr
        end)
    else
        for _, win in ipairs(A.nvim_list_wins()) do
            if A.nvim_win_get_buf(win) == bufnr then
                return true
            end
        end
    end

    return false
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
    if vim.iter then
        return vim.iter(A.nvim_list_bufs()):find(function(b)
            local bufname = collapse_bufname(A.nvim_buf_get_name(b))
            return bufname == name
        end)
    else
        for _, bufnr in ipairs(A.nvim_list_bufs()) do
            local bufname = collapse_bufname(A.nvim_buf_get_name(bufnr))
            if bufname == name then
                return bufnr
            end
        end
    end

    return nil
end

--- Get the time a file was last updated, or `nil` if <= the result of last check.
---
--- @param path string The absolute file path.
--- @param last_check integer The unix timestamp to check against. Defaults to `0`.
--- @return integer|nil time
local function file_updated(path, last_check)
    last_check = last_check or 0
    local stat = uv.fs_stat(path)
    if stat and stat.type == "file" and stat.mtime.sec > last_check then
        return stat.mtime.sec
    end

    return nil
end

--- @type watch.Watcher[]
---
--- Global list of watchers and associated data.
Watch.watchers = {}

--- @class watch.SplitConfig
---
--- @field enabled boolean Whether to open the watch in a new split. Defaults to `false`.
--- @field position '"above"'|'"below"'|'"right"'|'"left'" Where to place the split (above|below|right|left). Defaults to `below`.
--- @field size integer|nil The size of the split in rows (or columns if position is right or left). Defaults to `nil`.
--- @field focus boolean Whether to focus on the newly created split watcher. Defaults to `true`.
---
--- Configuration for watch.nvim.

--- @class watch.Config
---
--- @field refresh_rate integer The default refresh rate for a new watcher in milliseconds. Defaults to `500`.
--- @field close_on_stop boolean Whether to automatically delete the buffer when stopping a watcher. Defaults to `false`.
--- @field ANSI_enabled boolean Whether to enable ANSI colors in output. Requires Makaze/AnsiEsc.vim. Ignored if terminal is set to `true`. Defaults to `false`.
--- @field terminal boolean Whether to open in a terminal buffer. Automatically supports your terminal's built in ANSI colors. Has higher priority than ANSI_enabled. Defaults to `true`.
---
--- Configuration for watch.nvim.

--- @type watch.Config
Watch.config = {
    refresh_rate = 500,
    close_on_stop = false,
    split = {
        enabled = false,
        position = "below",
        size = nil,
        focus = true,
    },
    ANSI_enabled = false,
    terminal = true,
}

--- @class watch.SplitConfigOverride
---
--- @field enabled boolean Whether to open the watch in a new split. Defaults to `false`.
--- @field position? '"above"'|'"below"'|'"right"'|'"left'" Where to place the split (above|below|right|left). Defaults to `below`.
--- @field size? integer|nil The size of the split in rows (or columns if position is right or left). Defaults to `nil`.
--- @field focus? boolean Whether to focus on the newly created split watcher. Defaults to `true`.
---
--- Configuration for watch.nvim.

--- @class watch.ConfigOverride
---
--- @field refresh_rate? integer The default refresh rate for a new watcher in milliseconds. Defaults to `500`.
--- @field close_on_stop? boolean Whether to automatically delete the buffer when stopping a watcher. Defaults to `false`.
--- @field split? watch.SplitConfigOverride Configuration options for opening the watcher in a split.
--- @field ANSI_enabled? boolean Whether to enable ANSI colors in output. Requires Makaze/AnsiEsc.vim. Ignored if terminal is set to `true`. Defaults to `false`.
--- @field terminal? boolean Whether to open in a terminal buffer. Automatically supports your terminal's built in ANSI colors. Has higher priority than ANSI_enabled. Defaults to `true`.
---
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

    if opts.ANSI_enabled and not vim.fn.exists(":AnsiEsc") then
        opts.ANSI_enabled = false
        vim.notify(
            "[watch] WARNING: Makaze/AnsiEsc not loaded; disabling ANSI colors",
            vim.log.levels.WARN
        )
    end

    Watch.config =
        vim.tbl_deep_extend("force", Watch.config, vim.F.if_nil(opts, {}))
end

--- Sends a command to a terminal buffer and executes it.
---
--- @param bufnr integer The buffer number to update.
--- @param command string The command to send to the terminal.
Watch.update_term = function(bufnr, command)
    -- Save the current window ID and cursor position
    local original_win = A.nvim_get_current_win()
    local original_cursor = A.nvim_win_get_cursor(original_win)

    -- Check if terminal buffer
    local terminal_window = nil
    if A.nvim_get_option_value("buftype", { buf = bufnr }) == "terminal" then
        -- Find the window ID associated with the specified buffer number
        for _, win in ipairs(A.nvim_list_wins()) do
            if A.nvim_win_get_buf(win) == bufnr then
                terminal_window = win
                break
            end
        end
    end

    -- Switch to the terminal window
    if terminal_window then
        A.nvim_set_current_win(terminal_window)

        -- Send the command to the terminal buffer
        vim.cmd("set modifiable")
        A.nvim_buf_set_lines(bufnr, 0, -1, false, {})
        vim.cmd("set nomodified")
        vim.fn.termopen(command .. "\n")
        vim.cmd("set modifiable")

        -- Restore the original window and cursor position
        A.nvim_set_current_win(original_win)
        A.nvim_win_set_cursor(original_win, original_cursor)
    else
        vim.notify(
            "[watch] ERROR: Terminal buffer with bufnr "
                .. bufnr
                .. " not found",
            vim.log.levels.ERROR
        )
    end
end

--- Replaces the lines in a buffer while preserving the cursor.
---
--- @param lines table The lines to replace into the buffer.
--- @param bufnr integer The buffer number to update.
Watch.update_lines = function(lines, bufnr)
    -- Save current cursor position
    local save_cursor = A.nvim_win_get_cursor(0)

    -- Strip ANSI color codes from the output if unsupported
    local ANSI_loaded = vim.fn.exists("g:loaded_AnsiEsc")
    local bufname = collapse_bufname(A.nvim_buf_get_name(bufnr))
    local stripped_output = (Watch.config.ANSI_enabled and ANSI_loaded)
            and lines
        or {}
    if #stripped_output < 1 then
        for _, line in ipairs(lines) do
            local stripped_line = line:gsub("\27%[[%d;]*[mK]", "") -- Remove ANSI escape sequences
            table.insert(stripped_output, stripped_line)
        end
    elseif not Watch.watchers[bufname].ANSI_enabled then
        -- Check if ANSI is enabled
        if Watch.config.ANSI_enabled then
            A.nvim_buf_call(bufnr, function()
                A.nvim_command("AnsiEsc")
            end)
            Watch.watchers[bufname].ANSI_enabled = true
        end
    end

    -- Clear the buffer and insert the stripped output
    A.nvim_buf_set_lines(bufnr, 0, -1, false, stripped_output)

    -- Restore cursor position
    A.nvim_win_set_cursor(0, save_cursor)
end

--- Returns a function that updates the buffer's contents and preserves the cursor.
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

        local W = Watch.watchers[command]
        if W.file then
            local update = file_updated(W.file, W.last_updated)

            if update then
                Watch.watchers[command].last_updated = update
            else
                return
            end
        end

        -- Use terminal if set
        if Watch.config.terminal then
            Watch.update_term(bufnr, command)
            return
        end

        -- Execute your command and capture its output otherwise
        if vim.system then
            -- Use vim.system for async
            local code = vim.system(
                vim.split(command, " "),
                { text = true },
                function(out)
                    -- Need vim.schedule to use most actions inside of vim loop
                    vim.schedule(function()
                        -- Handle error
                        if out.code ~= 0 then
                            if Watch.watchers[command] then
                                Watch.kill(command)
                                vim.notify(
                                    "[watch] ! Stopping: " .. out.stderr,
                                    vim.log.levels.ERROR
                                )
                            end
                            return
                        end

                        Watch.update_lines(vim.split(out.stdout, "\n"), bufnr)
                    end)
                end
            )
        else
            -- Use vim.fn.jobstart for compatibility
            local args = vim.split(command, " ")
            local cmd = table.remove(args, 1)

            local stdout = uv.new_pipe(false)
            local stderr = uv.new_pipe(false)
            local results = {}
            local handle = nil

            handle = uv.spawn(
                cmd,
                {
                    args = args,
                    stdio = { nil, stdout, stderr },
                },
                vim.schedule_wrap(function()
                    stdout:read_stop()
                    stderr:read_stop()
                    stdout:close()
                    stderr:close()
                    if handle then
                        handle:close()
                    end

                    Watch.update_lines(results, bufnr)
                end)
            )

            local function onread(err, data)
                if err then
                    if Watch.watchers[command] then
                        Watch.kill(command)
                        vim.notify(
                            "[watch] ! Stopping: " .. err,
                            vim.log.levels.ERROR
                        )
                    end
                    return
                end
                if data then
                    local vals = vim.split(data, "\n")
                    for _, d in pairs(vals) do
                        table.insert(results, d)
                    end
                end
            end

            uv.read_start(stdout, onread)
            uv.read_start(stderr, onread)
        end
    end
end

--- Starts continually reloading a buffer's contents with a shell command. If the command is aleady being watched, then opens that buffer in the current window.
---
--- @param command string Shell command to watch. If `file` is given, then `%s` will expand to the filename.
--- @param refresh_rate? integer Time between reloads in milliseconds. Defaults to `watch.config.refresh_rate`. If `file` is provided, then it is increased to a minimum of 1000 ms.
--- @param bufnr? integer Buffer number to update. Defaults to a new buffer.
--- @param file? string The absolute path of the file to watch. Defaults to `nil`.
Watch.start = function(command, refresh_rate, bufnr, file)
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

    -- Expand %s to the filename
    if file then
        command = string.gsub(command, "%%s", file)
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

    -- Minimum 1000 ms if file check
    if file and refresh_rate < 1000 then
        vim.notify(
            "[watch] File watchers require refresh_rate >= 1000. Increasing to 1000 ms."
        )
        refresh_rate = 1000
    end

    -- Create a split based on configurations
    local split = Watch.config.split or {}
    if split and split.enabled then
        local position = split.position
        local size = split.size or ""

        if position == "above" then
            A.nvim_command("split | wincmd k | resize " .. size)
        elseif position == "right" then
            A.nvim_command(size .. "vsplit")
        elseif position == "left" then
            A.nvim_command("vsplit | wincmd h | vertical resize " .. size)
        else
            -- Must be "below" by default
            A.nvim_command(size .. "split")
        end
    end

    -- Get existing bufnr if bufname already exists
    bufnr = get_buf_by_name(command) or bufnr

    -- Create a new buffer if not
    if not bufnr then
        bufnr = A.nvim_create_buf(true, true)
        A.nvim_set_option_value("buftype", "nofile", { buf = bufnr })
        A.nvim_buf_set_name(bufnr, command)
    end

    -- Always set as current buffer when starting
    A.nvim_win_set_buf(0, bufnr)

    -- Unfocus the window if set to false
    if split and split.enabled then
        if not split.focus then
            A.nvim_command("wincmd p")
        end
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
        file = file,
        last_updated = 0,
        ANSI_enabled = false,
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
--- @param event? string|table The command name to stop. If string, then uses the string. If table, then uses `event.file`.
Watch.stop = function(event)
    -- Get the current buffer if it is a watcher
    local bufname = nil
    -- Count keys the hard way
    local watch_count = 0
    for _ in pairs(Watch.watchers) do
        watch_count = watch_count + 1
    end
    if not event then
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
            Watch.kill(command)
        end
        vim.notify("[watch] Stopped " .. watch_count .. " watchers")
    else
        local command = event.file or event
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
        Watch.kill(command)
        vim.notify("[watch] Stopped watching " .. command)
    end
end

--- Kills and cleans up a watcher.
---
--- `WARNING:` If `watch.config.close_on_stop` is set to `true`, then affected buffers will also be deleted.
---
--- @param command string The command name to kill.
Watch.kill = function(command)
    local W = Watch.watchers[command]
    if not W then
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
end

return Watch
