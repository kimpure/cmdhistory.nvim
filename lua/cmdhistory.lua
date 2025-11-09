local api = vim.api
local fn = vim.fn

--- @type string[]
local history = {}
local history_index = 0
local history_standard = 0
local history_size = 500
local history_path = fn.stdpath("data") .. "/cmdhistory"

local data_mute = { "q", "qa", "wq", "wqa" }
local cmdline_type = { ":" }

--- @param tab any[]
--- @param value any
--- @return number?
local function find(tab, value)
    for i=1, #tab do
        if value == tab[i] then
            return i
        end
    end
end

--- @param command string
--- @diagnostic disable-next-line
local function add_history(command)
    if command == "" then
        return
    end

	if history_standard == history_size then
		history_standard = 1
	else
		history_standard = history_standard + 1
	end

    history_index = history_standard
	history[history_standard] = command
end

--- @return string
--- @diagnostic disable-next-line
local function current_history()
    return history[history_index]
end

--- @return string?
--- @diagnostic disable-next-line
local function prev_history()
	if history_index - 1 ~= history_standard then
		if history[history_standard + 1] and history_index == 1 then
			history_index = history_size
		else
            if history_index == 1 then
                return nil
            else
                history_index = history_index - 1
            end
		end
    else
        return nil
	end

	return history[history_index]
end

--- @return string?
--- @diagnostic disable-next-line
local function next_history()
	if history_index ~= history_standard then
		if history[history_standard + 1] and history_index == history_size then
			history_index = 1
		else
			history_index = history_index + 1
		end
    else
        return nil
	end

	return history[history_index]
end

--- @param content string
--- @diagnostic disable-next-line
local function write_cmdline(content)
	local key_sequence = ":" .. "<C-U>" .. (content or "")
	local keys_to_feed = api.nvim_replace_termcodes(key_sequence, true, false, true)
	api.nvim_feedkeys(keys_to_feed, "nt", false)
end

--- @class CmdHistory
local M = {}

local is_init_movement = true

--- Fill in the previous command with cmdline
function M.prev_cmdline()
    if is_init_movement then
        is_init_movement = false
        write_cmdline(current_history())
        return
    end

    local command = prev_history()
    if command then
		write_cmdline(command)
    end
end

--- Fill in the next command with cmdline
function M.next_cmdline()
    if is_init_movement then
        return
    end

	local command = next_history()
    if command then
		write_cmdline(command)
    else
        write_cmdline("")
        is_init_movement = true
    end
end

--- Save to history
function M.save_commands()
	fn.writefile(history, history_path .. "/history")
end

--- @class CmdHistory.Options.History
--- @field size number Maximum number of records in history
--- @field path string Directory path to save history

--- @class CmdHistory.Options.Mute
--- @field data string[] Commands not to be saved

--- @class CmdHistory.Options
--- @field history CmdHistory.Options.History
--- @field mute CmdHistory.Options.Mute
--- @field default_keymap? boolean
--- @field cmdline_type? string[]

--- @param options? CmdHistory.Options
--- @return CmdHistory
function M.setup(options)
	options = options or {}
	options.history = options.history or {}

	history_path = options.history.path or history_path

    data_mute = options.mute or data_mute
    cmdline_type = options.cmdline_type or cmdline_type

	if fn.isdirectory(history_path) == 0 then
		fn.mkdir(history_path, "p")
	end

	if fn.filereadable(history_path .. "/history") == 0 then
		fn.writefile({}, history_path .. "/history")
	end

	history = fn.readfile(history_path .. "/history")
	history_size = options.history.size or 500
	history_standard = #history
	history_index = history_standard

	do
		local cmdline_data = ""
		local last_cmdline_data = ""

		api.nvim_create_autocmd("CmdlineChanged", {
			callback = function()
                if find(cmdline_type, fn.getcmdtype()) then
                    cmdline_data = fn.getcmdline()
                end
			end,
		})

		api.nvim_create_autocmd("CmdlineLeave", {
			callback = function()
				local line = vim.fn.getcmdline()
                local type = vim.fn.getcmdtype()

                if line == "" or not type == ":" then
                    return
                end

                if last_cmdline_data ~= cmdline_data and not find(data_mute, cmdline_data) then
					last_cmdline_data = cmdline_data
					add_history(cmdline_data)
				end

                history_index = history_standard
                is_init_movement = true
			end,
		})
	end

	api.nvim_create_autocmd("VimLeavePre", {
		callback = M.save_commands,
	})

	api.nvim_create_user_command("CmdHistory", function(opts)
		local args = opts.args

		if args == "Prev" then
			M.prev_cmdline()
		elseif args == "Next" then
			M.next_cmdline()
		elseif args == "Save" then
			M.save_commands()
		else
			vim.notify("Unknown argument: " .. arg, vim.log.levels.WARN)
		end
	end, {
		nargs = 1,
		complete = function()
			return { "Prev", "Next", "Save" }
		end,
	})

    if options.default_keymap == nil or options.default_keymap then
        vim.keymap.set("c", "<Up>", M.prev_cmdline)
        vim.keymap.set("c", "<Down>", M.next_cmdline)
    end

	return M
end

return M
