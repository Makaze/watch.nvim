--- @class watch.Watcher
---
--- @field command string The command to watch. Serves as the name of the watcher.
--- @field refresh_rate integer The refresh rate for the watcher in milliseconds.
--- @field bufnr integer The buffer number attached to the watcher.
--- @field timer timer The buffer number attached to the watcher.

local M = {}

local A = vim.api
local err = A.nvim_err_write

--- Check if a buffer is visible
---
--- @param bufnr integer The buffer number to check
--- @return boolean visible
local function visible(bufnr)
    for _, win_id in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win_id) == bufnr then
            return true
        end
    end
    return false
end

-- --- @type integer | nil
-- ---
-- --- The buffer number to load into
-- M.buf = nil
-- --- @type integer | nil

--- @type watch.Watcher[]
---
--- Global list of watchers and associated data
Watchers = Watchers or {}

--- Setup the plugin.
---
--- @param opts table Unused
M.setup = function(opts)
    Watchers = Watchers or {}
end

--- Replace buffer's contents with a shell command and preserve the cursor
---
--- @param command string Shell command
--- @param buf integer The buffer number to update
--- @return function update Steps to take upon rerunning
M.update = function(command, buf)
    return function()
        -- Do nothing if not visible
        if not visible(buf) then
            return
        end

        -- Save current cursor position
        local save_cursor = A.nvim_win_get_cursor(0)

        -- Execute your command and capture its output
        local output = vim.fn.systemlist(command)

        -- Strip ANSI color codes from the output
        local stripped_output = {}
        for _, line in ipairs(output) do
            local stripped_line = line:gsub("\27%[[%d;]*[mK]", "") -- Remove ANSI escape sequences
            table.insert(stripped_output, stripped_line)
        end

        -- Clear the buffer and insert the stripped output
        A.nvim_buf_set_lines(buf, 0, -1, false, stripped_output)

        -- Restore cursor position
        A.nvim_win_set_cursor(0, save_cursor)
    end
end

--- Start continually reloading a buffer's contents with a shell command. If the
--- command is aleady being watched, opens that buffer in the current window.
---
--- @param command string Shell command
--- @param refresh_rate integer? Time between reloads in milliseconds. Default 500
--- @param buf integer? Buffer number to update. Default new buffer
M.start = function(command, refresh_rate, buf)
    local uv = vim.loop or vim.uv

    -- Open the buffer if already running
    if Watchers[command] then
        buf = Watchers[command].bufnr
        vim.notify(
            "[watch] "
                .. command
                .. " was already being watched on bufnr="
                .. buf
                .. ". Switching..."
        )
        A.nvim_win_set_buf(0, buf)
        return
    end

    -- Default to 500 ms
    if not refresh_rate or refresh_rate <= 0 then
        refresh_rate = 500
    end

    -- Create a new buffer
    if not buf then
        buf = A.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(buf, command)
        -- Automatically delete buffer when no longer visible
        vim.api.nvim_set_option_value("buflisted", "true", { buf = buf })
        A.nvim_win_set_buf(0, buf)
    end

    -- Set up a timer to run the function every 500ms
    local timer = uv.new_timer()
    timer:start(
        refresh_rate,
        refresh_rate,
        vim.schedule_wrap(M.update(command, buf))
    )

    --- @type watch.Watcher
    local watcher = {
        command = command,
        bufnr = buf,
        refresh_rate = refresh_rate,
        timer = timer,
    }

    Watchers[command] = watcher

    local group = A.nvim_create_augroup("WatchCleanUp", { clear = true })

    -- Stop the timer when the buffer is unloaded or when quitting Neovim
    A.nvim_create_autocmd({ "BufUnload", "VimLeavePre" }, {
        group = group,
        buffer = buf,
        callback = M.stop,
    })
end

--- Stop watching and detach from the buffer
---
--- @param event table? The event table used to choose what to stop. Default all
M.stop = function(event)
    if not event or event.event == "VimLeavePre" then
        for _, command in ipairs(Watchers) do
            Watchers[command].timer:stop()
            Watchers[command] = nil
            vim.notify("[watch] Stopped watching " .. command)
        end
    else
        local command = event.file or event
        if not Watchers[command] then
            vim.notify("[watch] Error: Already not watching " .. command)
            return
        end
        Watchers[command].timer:stop()
        Watchers[command] = nil
        vim.notify("[watch] Stopped watching " .. command)
    end
end

return M
