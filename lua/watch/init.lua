local M = {}

local A = vim.api

--- @type integer | nil
---
--- The buffer number to load into
M.buf = nil

M.setup = function(opts)
    -- For compatability only
end

--- Replace buffer's contents with a shell command and preserve the cursor
---
--- @param command string Shell command
--- @return function update Steps to take upon rerunning
M.update = function(command)
    return function()
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
        A.nvim_buf_set_lines(M.buf, 0, -1, false, stripped_output)

        -- Restore cursor position
        A.nvim_win_set_cursor(0, save_cursor)
    end
end

--- Start continually reloading a buffer's contents with a shell command
---
--- @param command string Shell command
--- @param refresh_rate integer? Time between reloads in milliseconds. Default 500
M.start = function(command, refresh_rate)
    local uv = vim.loop or vim.uv

    -- Default to 500 ms
    if not refresh_rate or refresh_rate <= 0 then
        refresh_rate = 500
    end

    -- Create a new buffer
    if not M.buf then
        M.buf = A.nvim_create_buf(false, true)
        -- Automatically delete buffer when no longer visible
        vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = M.buf })
        -- A.nvim_command "split"
        A.nvim_win_set_buf(0, M.buf)
    end

    -- Set up a timer to run the function every 500ms
    M.watch_timer = uv.new_timer()
    M.watch_timer:start(
        refresh_rate,
        refresh_rate,
        vim.schedule_wrap(M.update(command))
    )

    local group = A.nvim_create_augroup("WatchCleanUp", { clear = true })

    -- Stop the timer when the buffer is unloaded or when quitting Neovim
    A.nvim_create_autocmd({ "BufUnload", "VimLeavePre" }, {
        group = group,
        buffer = M.buf,
        callback = M.stop,
    })
end

--- Stop watching and detach from the buffer
M.stop = function()
    M.buf = nil
    M.watch_timer:stop()
end

return M
