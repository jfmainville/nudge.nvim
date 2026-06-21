local M = {}

local state = { files = {} }

function M.add(filepath)
	local abs = vim.fn.fnamemodify(filepath, ":p")
	for _, f in ipairs(state.files) do
		if f == abs then
			return
		end
	end
	table.insert(state.files, abs)
end

function M.remove(filepath)
	local abs = vim.fn.fnamemodify(filepath, ":p")
	for i, f in ipairs(state.files) do
		if f == abs then
			table.remove(state.files, i)
			return
		end
	end
end

function M.clear()
	state.files = {}
end

function M.get_files()
	return vim.list_extend({}, state.files)
end

function M.get_file_contents()
	local results = {}
	for _, filepath in ipairs(state.files) do
		local ok, lines = pcall(vim.fn.readfile, filepath)
		if ok then
			local ft = vim.filetype.match({ filename = filepath }) or "text"
			table.insert(results, {
				path = filepath,
				content = table.concat(lines, "\n"),
				filetype = ft,
			})
		end
	end
	return results
end

local open_add_picker

open_add_picker = function()
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	require("telescope.builtin").find_files({
		prompt_title = "Add File to Context  <Tab> multi-select · <C-d> remove",
		attach_mappings = function(prompt_bufnr, map)
			actions.select_default:replace(function()
				local picker = action_state.get_current_picker(prompt_bufnr)
				local selections = picker:get_multi_selection()
				if #selections == 0 then
					local entry = action_state.get_selected_entry()
					if entry then
						selections = { entry }
					end
				end
				actions.close(prompt_bufnr)
				for _, entry in ipairs(selections) do
					local filepath = entry.path or vim.fn.fnamemodify(entry.value or entry[1], ":p")
					M.add(filepath)
				end
				if #selections > 0 then
					vim.notify(
						("Nudge: added %d file(s) to context (%d total)"):format(#selections, #state.files),
						vim.log.levels.INFO
					)
				end
			end)

			local function remove_from_context()
				local entry = action_state.get_selected_entry()
				if not entry then
					return
				end
				local filepath = entry.path or vim.fn.fnamemodify(entry.value or entry[1], ":p")
				local before = #state.files
				M.remove(filepath)
				if #state.files < before then
					vim.notify(
						("Nudge: removed from context: %s (%d remaining)"):format(
							vim.fn.fnamemodify(filepath, ":t"),
							#state.files
						),
						vim.log.levels.INFO
					)
				else
					vim.notify(
						("Nudge: %s is not in context"):format(vim.fn.fnamemodify(filepath, ":t")),
						vim.log.levels.WARN
					)
				end
			end

			for _, mode in ipairs({ "i", "n" }) do
				map(mode, "<C-d>", remove_from_context)
			end

			return true
		end,
	})
end

local function open_manager_picker()
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	local function make_finder()
		return finders.new_table({
			results = M.get_files(),
			entry_maker = function(entry)
				return {
					value = entry,
					display = vim.fn.fnamemodify(entry, ":~:."),
					ordinal = entry,
					path = entry,
				}
			end,
		})
	end

	pickers
		.new({}, {
			prompt_title = "Context Files  <CR> open · <C-d> remove · <C-a> clear all · <C-n> add",
			finder = make_finder(),
			sorter = conf.generic_sorter({}),
			previewer = conf.file_previewer({}),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					local selection = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					if selection then
						vim.cmd("edit " .. vim.fn.fnameescape(selection.value))
					end
				end)

				local function remove_selected()
					local selection = action_state.get_selected_entry()
					if not selection then
						return
					end
					M.remove(selection.value)
					local files = M.get_files()
					if #files == 0 then
						actions.close(prompt_bufnr)
						vim.notify("Nudge: context is now empty", vim.log.levels.INFO)
					else
						action_state.get_current_picker(prompt_bufnr):refresh(make_finder(), { reset_prompt = false })
						vim.notify(
							("Nudge: removed from context: %s"):format(vim.fn.fnamemodify(selection.value, ":t")),
							vim.log.levels.INFO
						)
					end
				end

				local function clear_all()
					M.clear()
					actions.close(prompt_bufnr)
					vim.notify("Nudge: context cleared", vim.log.levels.INFO)
				end

				local function add_new()
					actions.close(prompt_bufnr)
					open_add_picker()
				end

				for _, mode in ipairs({ "i", "n" }) do
					map(mode, "<C-d>", remove_selected)
					map(mode, "<C-a>", clear_all)
					map(mode, "<C-n>", add_new)
				end

				return true
			end,
		})
		:find()
end

function M.open_picker()
	local ok = pcall(require, "telescope")
	if not ok then
		vim.notify("Nudge: telescope.nvim is required for file context management", vim.log.levels.ERROR)
		return
	end

	if #state.files == 0 then
		open_add_picker()
	else
		open_manager_picker()
	end
end

return M
