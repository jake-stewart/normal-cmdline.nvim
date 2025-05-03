local function restore_winviews(winviews)
    for win_id, winview in pairs(winviews) do
        pcall(vim.api.nvim_win_call, win_id, function()
            pcall(vim.fn.winrestview, winview)
        end)
    end
end

local function save_winviews()
    local win_ids = vim.api.nvim_tabpage_list_wins(0)
    local winviews = {}
    for _, win_id in ipairs(win_ids) do
        winviews[win_id] = vim.api.nvim_win_call(
            win_id, vim.fn.winsaveview)
    end
    return winviews
end

local HIGHLIGHTS = {
    "Normal",
    "CursorLine",
    "FloatBorder",
    "Search",
    "CurSearch",
    "CursorLineSign",
    "CursorLineNr",
    "LineNr",
}

--- @type {[string]: string}
local TERM_CODES = setmetatable({}, {
    __index = function(t, k)
        local key = k:lower()
            :gsub("ctrl_", "c-")
            :gsub("meta_", "m-")
            :gsub("alt_", "a-")
            :gsub("shift_", "s-")
            :gsub("super_", "d-")
            :gsub("cmd_", "d-")
            :gsub("_", "-")
        t[k] = vim.api.nvim_replace_termcodes(
            "<" .. key .. ">", true, true, true)
        return t[k]
    end
})

--- @param lines string[]
--- @return integer
local function calculateHeight(lines)
    local buffer = table.concat(lines, "\n")
    local columns = vim.o.columns - 2
    local height = 1
    local i = 0
    while i < #buffer do
        local char = vim.fn.strpart(buffer, i, 1, 1)
        local len
        if char == "\n" then
            len = 2
        elseif char == "\t" then
            len = 2
        else
            len = vim.fn.strdisplaywidth(char)
        end
        if columns - len < 0 then
            height = height + 1
            columns = vim.o.columns
        end
        columns = columns - len
        i = i + #char
    end
    return height
end

--- @class CmdLine
--- @field options? table
--- @field lines integer
--- @field winviews? table<vim.fn.winrestview.dict>
--- @field win? integer
--- @field buf? integer
--- @field type? string
--- @field ns integer
local CmdLine = {
    lines = 0,
    ns = vim.api.nvim_create_namespace("NormalCmdLine"),
}
setmetatable(CmdLine, CmdLine)

function CmdLine:update_height(lines, forceUpdate)
    local height = calculateHeight(lines)
    vim.api.nvim_win_set_config(self.win, {
        height = math.max(vim.o.cmdheight, height)
    })
    if #lines > 1 then
        vim.api.nvim_buf_set_lines(self.buf, 0, -1, true, {
            table.concat(lines, TERM_CODES.ctrl_m)
        })
    end
    if height ~= self.lines or forceUpdate then
        vim.api.nvim_buf_clear_namespace(self.buf, self.ns, 0, -1)
        if height == 1 then
            vim.wo.statuscolumn = ":"
        else
            vim.wo.statuscolumn = ""
            vim.api.nvim_buf_set_extmark(self.buf, self.ns, 0, 0, {
                virt_text = {{self.type, "Normal"}},
                virt_text_pos = "inline",
                right_gravity = false,
            })
        end
        self.lines = height
    end
end

function CmdLine:restore_settings()
    if self.options then
        vim.o.ruler = self.options.ruler
        vim.o.showmode = self.options.showmode
        vim.o.titlestring = self.options.titlestring
        self.options = nil
    end
    if self.winviews then
        restore_winviews(self.winviews)
        self.winviews = nil
    end
end

function CmdLine:enter_insert(callback)
    local newcontent = vim.api.nvim_buf_get_lines(self.buf, 0, -1, true)

    local cursor = vim.api.nvim_win_get_cursor(self.win)
    local total_bytes = 0
    for i = 1, cursor[1] - 1 do
        total_bytes = total_bytes + #newcontent[i] + 1
    end
    total_bytes = total_bytes + cursor[2]

    vim.api.nvim_feedkeys(TERM_CODES.esc .. self.type, "nt", false)

    vim.schedule(function()
        vim.api.nvim_win_close(self.win, true)
        self:restore_settings()
        vim.fn.setcmdline(table.concat(newcontent, TERM_CODES.ctrl_m), total_bytes + 1)
        if callback then
            callback()
        end
    end)
end

function CmdLine:killBuffer()
    if self.buf then
        vim.api.nvim_buf_delete(self.buf, { force = true })
        self.buf = nil
    end
end

function CmdLine:createBuffer(mappings)
    self.buf = vim.api.nvim_create_buf(false, true)
    if self.buf <= 0 then
        error("failed to create buf")
    end

    vim.api.nvim_create_autocmd("TextChanged", {
        buffer = self.buf,
        callback = function()
            local cursor = vim.api.nvim_win_get_cursor(self.win)
            local lines = vim.api.nvim_buf_get_lines(
                self.buf, 0, -1, true)
            local total_bytes = 0
            for i = 1, cursor[1] - 1 do
                total_bytes = total_bytes + #lines[i]
            end
            total_bytes = total_bytes + cursor[2]
            self:update_height(lines)
            vim.api.nvim_win_set_cursor(self.win, { 1, total_bytes })
        end
    })

    vim.api.nvim_create_autocmd("InsertEnter", {
        buffer = self.buf,
        callback = function()
            if vim.v.insertmode == "i" then
                self:enter_insert()
            end
        end
    })

    vim.api.nvim_create_autocmd("WinLeave", {
        buffer = self.buf,
        callback = function()
            if self.win then
                self:restore_settings()
                vim.api.nvim_win_close(self.win, true)
                self.win = nil
            end
        end
    })

    for k, v in pairs(mappings) do
        vim.keymap.set("n", k, v, { buffer = self.buf })
    end

end

function CmdLine:enter_normal(type, mappings, hl)
    if not self.winviews then
        self.winviews = save_winviews()
    end
    local content = vim.fn.getcmdline()
    local pos = vim.fn.getcmdpos()

    if not self.buf then
        self.history_idx = 0
        self:createBuffer(mappings)
    end
    vim.api.nvim_buf_set_lines(self.buf, 0, -1, true, { content })

    vim.api.nvim_feedkeys(
        TERM_CODES.ctrl_e
            .. TERM_CODES.ctrl_u
            .. TERM_CODES.ctrl_c,
        "nt", false)

    self.type = type
    if self.options == nil then
        self.options = {
            ruler = vim.o.ruler,
            showmode = vim.o.showmode,
            titlestring = vim.o.titlestring,
        }
        local width = math.floor(
            vim.o.columns * (vim.o.titlelen / 100))
        vim.o.titlestring = string.gsub(
            vim.api.nvim_eval_statusline(
                vim.o.titlestring, { maxwidth = width }
            ).str,
            "%%",
            "%%%%"
        )
        vim.o.ruler = false
        vim.o.showmode = false
    end

    self.win = vim.api.nvim_open_win(self.buf, true, {
        anchor = "NW",
        relative = "editor",
        style = "minimal",
        row = vim.o.lines,
        col = 0,
        width = vim.o.columns,
        zindex = 1000,
        height = math.max(1, vim.o.cmdheight)
    })

    local hl_buffer = {}
    for _, name in ipairs(HIGHLIGHTS) do
        table.insert(hl_buffer, name .. ":" .. hl)
    end

    vim.wo.winhighlight = table.concat(hl_buffer, ",")
    vim.wo.breakindent = false
    vim.wo.breakindentopt = ""
    vim.wo.linebreak = false
    vim.wo.wrap = true
    vim.wo.signcolumn = "no"
    vim.wo.list = true

    local listchars = vim.opt.listchars:get()
    listchars.tab = nil
    vim.opt_local.listchars = listchars

    self:update_height({ content }, true)
    restore_winviews(self.winviews)
    vim.schedule(function()
        restore_winviews(self.winviews)
        vim.defer_fn(function()
            vim.api.nvim_win_set_cursor(
                self.win, { 1, math.max(pos - 2, 0) })
        end, 0)
    end)
end

function CmdLine:cancel()
    self:enter_insert(function()
        vim.api.nvim_feedkeys(TERM_CODES.ctrl_c, "nt", false)
        self:killBuffer()
    end)
end

function CmdLine:accept()
    self:enter_insert(function()
        vim.api.nvim_feedkeys(TERM_CODES.cr, "nt", false)
        self:killBuffer()
    end)
end

function CmdLine:reset()
    vim.api.nvim_buf_set_lines(self.buf, 0, -1, true, {})
    vim.api.nvim_feedkeys("i", "nt", false)
end

function CmdLine:seek_history(direction)
    local history_idx = (self.history_idx or -1) - direction
    if history_idx <= 0 then
        history_idx = 0
    elseif history_idx >= vim.fn.histnr(self.type) then
        history_idx = vim.fn.histnr(self.type)
    end
    if history_idx == self.history_idx then
        return
    end
    local item
    if history_idx == 0 then
        item = self.lastHistoryItem or ""
    else
        item = vim.fn.histget(self.type, -history_idx)
    end
    if self.history_idx == 0 then
        self.lastHistoryItem = table.concat(
            vim.api.nvim_buf_get_lines(self.buf, 0, -1, true),
            TERM_CODES.ctrl_m)
    end
    self.history_idx = history_idx
    local undolevels = vim.bo.undolevels
    vim.bo.undolevels = -1
    vim.api.nvim_buf_set_lines(self.buf, 0, -1, true, { item })
    vim.bo.undolevels = undolevels
    vim.api.nvim_feedkeys("$", "nt", false)
end

local M = {}

M.history = {
    seek = function(direction)
        CmdLine:seek_history(direction)
    end,
    next = function()
        CmdLine:seek_history(1)
    end,
    prev = function()
        CmdLine:seek_history(-1)
    end
}

function M.cancel()
    CmdLine:cancel()
end

function M.accept()
    CmdLine:accept()
end

function M.reset()
    CmdLine:reset()
end

function M.setup(opts)
    opts = vim.tbl_extend("keep", opts or {}, {
        key = "<esc>",
        hl = "Normal",
        mappings = {
            k = M.history.prev,
            j = M.history.next,
            ["<cr>"] = M.accept,
            ["<esc>"] = M.cancel,
            ["<c-c>"] = M.cancel,
            [":"] = M.reset,
        },
    })

    local key_termcodes = vim.api.nvim_replace_termcodes(
        opts.key, true, true, true)

    vim.keymap.set("c", opts.key, function()
        if vim.fn.getcmdwintype() == ""
            and vim.fn.getcmdtype() == ":"
        then
            CmdLine:enter_normal(":", opts.mappings, opts.hl)
        else
            vim.api.nvim_feedkeys(key_termcodes, "nt", false)
        end
        if vim.fn.getcmdwintype() ~= "" then
            vim.api.nvim_feedkeys(key_termcodes, "nt", false)
            return
        end
    end)
end

return M
