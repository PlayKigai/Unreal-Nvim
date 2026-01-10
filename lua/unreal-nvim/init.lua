---@diagnostic disable: undefined-global
local UE = {}
local has_lspconfig, lspconfig = pcall(require, "lspconfig")
local has_telescope, telescope = pcall(require, "telescope.builtin")
local utils = require("unreal-nvim.utils")
local workspace_detect_group = vim.api.nvim_create_augroup("UnrealWorkspaceDetect", { clear = true })
local workspace_detect_autocmd
local WORKSPACE_EVENTS = { "VimEnter", "BufEnter", "BufWinEnter", "DirChanged" }

local function register_keymaps(maps)
	if type(maps) ~= "table" or vim.tbl_isempty(maps) then
		return
	end
	for keymap, info in pairs(maps) do
		if not info.needs_telescope or has_telescope then
			vim.keymap.set("n", keymap, info.cmd, {
				desc = info.desc,
				silent = true,
			})
		end
	end
end

local UNREAL_EXCLUDE_GLOBS = {
	"--glob",
	"!**/.git/**",
	"--glob",
	"!**/Intermediate/**",
	"--glob",
	"!**/Binaries/**",
	"--glob",
	"!**/DerivedDataCache/**",
	"--glob",
	"!**/Saved/**",
	"--glob",
	"!**/Build/**",
	"--glob",
	"!**/Content/**",
	"--glob",
	"!**/.{vscode,idea,vs,cache}/**",
	"--glob",
	"!**/*.{dll,exe,so,dylib,lib,a,o,obj,pdb,rsp,idx,clangd}",
	"--glob",
	"!**/*.{uasset,umap}",
	"--glob",
	"!**/*.{png,jpg,jpeg,gif,svg,webp,bmp,psd,tga,tif,tiff}",
}

---@type { engine_path: string?; auto_register_clangd: boolean; keymaps: table<string, table>? }
local config = { engine_path = nil, auto_register_clangd = false, keymaps = nil }
local features_enabled = false

local function load_engine_from_info(uproj)
	local project_folder = vim.fn.fnamemodify(uproj, ":h")
	local info_file = project_folder .. "/.ueinfo"
	local fd = io.open(info_file, "r")
	if not fd then
		return nil
	end
	local line = fd:read("*l")
	fd:close()
	local p = line:match("^UEPath=(.+)")
	if utils.is_valid_engine_path(p) then
		return utils.save_engine_path(p, uproj)
	end
end

local function get_engine_root(callback)
	if config.engine_path and utils.is_valid_engine_path(config.engine_path) then
		return callback(config.engine_path)
	end
	local cached_root = utils.get_cached_engine_root()
	if cached_root then
		return callback(cached_root)
	end
	local uproj = utils.find_uproject()
	if uproj then
		local info_root = load_engine_from_info(uproj)
		if info_root then
			return callback(info_root)
		end
	end
	local env = os.getenv("UE_ENGINE_PATH")
	if utils.is_valid_engine_path(env) then
		return callback(utils.save_engine_path(env, uproj))
	end
	local engine_root = utils.find_engine_root()
	if utils.is_valid_engine_path(engine_root) then
		return callback(utils.save_engine_path(engine_root, uproj))
	end
	vim.ui.input({ prompt = "Enter Unreal Engine path:" }, function(input)
		if not input or input == "" then
			vim.notify("[Unreal] Engine path selection cancelled.", vim.log.levels.WARN)
			return callback(nil)
		end
		local real = vim.loop.fs_realpath(input)
		if utils.is_valid_engine_path(real) then
			return callback(utils.save_engine_path(real, uproj))
		else
			vim.notify("[Unreal] Invalid engine path: " .. input, vim.log.levels.ERROR)
			return callback(nil)
		end
	end)
end

local function ensure_output_window()
	if UE.win and vim.api.nvim_win_is_valid(UE.win) then
		vim.api.nvim_buf_set_lines(UE.buf, 0, -1, false, {})
		return
	end
	UE.buf = vim.api.nvim_create_buf(false, true)
	local cols, lines = vim.o.columns, vim.o.lines
	local w, h = math.floor(cols * 0.5), math.floor(lines * 0.3)
	-- Top right floating window
	UE.win = vim.api.nvim_open_win(UE.buf, false, {
		relative = "editor",
		anchor = "NE",
		row = 0,
		col = cols,
		width = w,
		height = h,
		style = "minimal",
		border = "rounded",
		focusable = true,
		zindex = 50,
	})
	vim.api.nvim_set_option_value("winblend", 10, { win = UE.win })
	vim.api.nvim_set_option_value("wrap", true, { win = UE.win })
	vim.api.nvim_set_option_value("mouse", "a", { win = UE.win })
	vim.api.nvim_set_option_value("filetype", "unreal_output", { buf = UE.buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = UE.buf })
	vim.api.nvim_set_option_value("modifiable", true, { buf = UE.buf })
	vim.api.nvim_set_option_value("readonly", false, { buf = UE.buf })
	-- Easily close the output window
	vim.api.nvim_buf_set_keymap(
		UE.buf,
		"n",
		"q",
		"<cmd>q<CR>",
		{ noremap = true, silent = true, desc = "Close Unreal Output" }
	)
	vim.api.nvim_buf_set_keymap(
		UE.buf,
		"n",
		"<Esc>",
		"<cmd>q<CR>",
		{ noremap = true, silent = true, desc = "Close Unreal Output" }
	)
end

local function append_output(lines)
	if not (UE.buf and vim.api.nvim_buf_is_valid(UE.buf)) then
		return
	end
	for i, l in ipairs(lines) do
		lines[i] = l:gsub("%s+$", "")
	end
	vim.api.nvim_buf_set_lines(UE.buf, -1, -1, false, lines)
	if UE.win and vim.api.nvim_win_is_valid(UE.win) then
		vim.api.nvim_win_set_cursor(UE.win, { vim.api.nvim_buf_line_count(UE.buf), 0 })
	end
end

local MODES = { BUILD = "build", HEADER = "header", COMPILE = "compile" }
local CONFIGS = { "DebugGame", "Development", "Shipping", "Debug", "Test" }

local function make_ubt_cmd(mode, uproj, target, plat, conf, eng)
	local is_win = vim.fn.has("win32") == 1
	local script = eng
		.. "/Engine/Build/BatchFiles/"
		.. (is_win and "Build.bat" or (vim.loop.os_uname().sysname == "Darwin" and "Mac/Build.sh" or "Linux/Build.sh"))
	local parts = { vim.fn.shellescape(script), target, plat, conf }
	if uproj then
		parts[#parts + 1] = (is_win and "-Project=" or "-project=") .. vim.fn.shellescape(uproj)
	end
	if mode == MODES.HEADER then
		parts[#parts + 1] = "-SkipBuild"
	elseif mode == MODES.COMPILE then
		local out = uproj and vim.fn.fnamemodify(uproj, ":p:h") or eng
		vim.list_extend(parts, {
			"-Mode=GenerateClangDatabase",
			"-OutputDir=" .. vim.fn.shellescape(out),
			"-game",
			"-engine",
			"-NoHotReload",
		})
	end
	return table.concat(parts, " ")
end

local function run_ubt(scope, mode)
	local uproj = scope == "Project" and utils.find_uproject()
	if scope == "Project" and not uproj then
		return vim.notify("[Unreal][Project] .uproject not found", vim.log.levels.ERROR)
	end
	get_engine_root(function(root)
		if not root then
			return vim.notify(string.format("[Unreal][%s] engine path missing", scope), vim.log.levels.ERROR)
		end
		local base = (scope == "Project" and vim.fn.fnamemodify(uproj, ":h") or root)
		local pat = base .. (scope == "Project" and "/Source/*.Target.cs" or "/Engine/Source/**/*.Target.cs")
		local files = vim.fn.glob(pat, true, true)
		local targets = {}
		for _, f in ipairs(files) do
			targets[#targets + 1] = vim.fn.fnamemodify(f, ":t:r"):gsub("%.Target$", "")
		end
		if #targets == 0 then
			local name = vim.fn.fnamemodify(uproj or root, ":t:r")
			targets = { name .. (scope == "Project" and "Editor" or "") }
			vim.notify(string.format("[Unreal][%s] defaulting to %s", scope, targets[1]), vim.log.levels.WARN)
		end
		local plat = vim.fn.has("win32") == 1 and "Win64"
			or (vim.loop.os_uname().sysname == "Darwin" and "Mac" or "Linux")
		vim.notify(string.format("[Unreal][%s] platform: %s", scope, plat), vim.log.levels.INFO)

		vim.ui.select(targets, { prompt = "Target (" .. scope .. "):" }, function(t)
			if not t then
				return
			end
			vim.ui.select(CONFIGS, { prompt = "Configuration:" }, function(c)
				if not c then
					return
				end
				local cmd = make_ubt_cmd(mode, uproj, t, plat, c, root)
				ensure_output_window()
				append_output({ "Starting UBT:", cmd, "" })
				vim.fn.jobstart(cmd, {
					cwd = base,
					on_stdout = function(_, d)
						append_output(d)
					end,
					on_stderr = function(_, d)
						append_output(d)
					end,
					on_exit = function(_, code)
						append_output({ "", "Exit code: " .. code })
						vim.notify(
							string.format("[Unreal][%s] done (%d)", scope, code),
							code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR
						)
						if code == 0 then
							vim.cmd("LspRestart clangd")
						end
					end,
				})
			end)
		end)
	end)
end

local function write_clangd(root)
	local path = root and (root .. "/.clangd")
	if not path then
		return vim.notify("[Unreal] .clangd root not found", vim.log.levels.ERROR)
	end
	local fd = io.open(path, "w")
	if not fd then
		return vim.notify("[Unreal] Failed to write .clangd", vim.log.levels.ERROR)
	end
	fd:write(table.concat({
		"CompileFlags:",
		'  Add: ["-std=c++17", "--background-index", "--clang-tidy"]',
		"Index:",
		"  Background: true",
		"Diagnostics:",
		'  Suppress: ["unused-variable", "unused-parameter"]',
		"ClangTidy:",
		'  Add: ["modernize*", "performance*"]',
	}, "\n") .. "\n")
	fd:close()
	vim.notify("[Unreal] Generated .clangd at " .. path, vim.log.levels.INFO)
	vim.cmd("LspRestart clangd")
end

local function register_unreal_commands()
	local function add_command(name, callback)
		vim.api.nvim_create_user_command(name, callback, {})
	end

	for _, scope in ipairs({ "Project", "Engine" }) do
		add_command("UEBuild" .. scope, function()
			run_ubt(scope, MODES.BUILD)
		end)
		add_command("UEHeader" .. scope, function()
			run_ubt(scope, MODES.HEADER)
		end)
		add_command("UECompileCommands" .. scope, function()
			run_ubt(scope, MODES.COMPILE)
		end)
		add_command("UEClangdConfig" .. scope, function()
			if scope == "Project" then
				local u = utils.find_uproject()
				if u then
					write_clangd(vim.fn.fnamemodify(u, ":h"))
				end
			else
				get_engine_root(function(r)
					if r then
						write_clangd(r)
					end
				end)
			end
		end)
	end

	add_command("UECwdProject", function()
		local u = utils.find_uproject()
		if u then
			local root = vim.fn.fnamemodify(u, ":h")
			vim.cmd("cd " .. vim.fn.fnameescape(root))
			vim.notify("[Unreal] CWD→Project: " .. root, vim.log.levels.INFO)
		else
			vim.notify("[Unreal] Project root not found.", vim.log.levels.ERROR)
		end
	end)

	add_command("UECwdEngine", function()
		get_engine_root(function(r)
			if r then
				vim.cmd("cd " .. vim.fn.fnameescape(r))
				vim.notify("[Unreal] CWD→Engine: " .. r, vim.log.levels.INFO)
			end
		end)
	end)

	if has_telescope then
		local find_cmd = vim.iter({ { "rg", "--files", "--hidden" }, UNREAL_EXCLUDE_GLOBS }):flatten():totable()
		local grep_args = vim.iter({ { "--hidden" }, UNREAL_EXCLUDE_GLOBS }):flatten():totable()

		add_command("TelescopeUnrealFind", function()
			local roots = {}
			local u = utils.find_uproject()
			if u then
				table.insert(roots, vim.fn.fnamemodify(u, ":h"))
			end
			get_engine_root(function(r)
				if r then
					table.insert(roots, r)
				end
				telescope.find_files({ prompt_title = "Unreal Find", search_dirs = roots, find_command = find_cmd })
			end)
		end)

		add_command("TelescopeUnrealGrep", function()
			local roots = {}
			local u = utils.find_uproject()
			if u then
				table.insert(roots, vim.fn.fnamemodify(u, ":h"))
			end
			get_engine_root(function(r)
				if r then
					table.insert(roots, r)
				end
				telescope.live_grep({ prompt_title = "Unreal Grep", search_dirs = roots, additional_args = grep_args })
			end)
		end)
	end

	register_keymaps(config.keymaps)
end

local function detect_start_path(ev)
	if ev then
		local path = ev.file
		if (not path or path == "") and ev.buf and vim.api.nvim_buf_is_valid(ev.buf) then
			path = vim.api.nvim_buf_get_name(ev.buf)
		end
		if path and path ~= "" then
			return path
		end
	end
	return vim.fn.getcwd()
end

local function enable_unreal_features(start)
	if features_enabled then
		return true
	end
	if not utils.is_unreal_workspace(start) then
		return false
	end
	features_enabled = true
	register_unreal_commands()
	return true
end

local function workspace_detection_callback(ev)
	if enable_unreal_features(detect_start_path(ev)) and workspace_detect_autocmd then
		vim.api.nvim_del_autocmd(workspace_detect_autocmd)
		workspace_detect_autocmd = nil
	end
end

local function schedule_workspace_detection()
	if workspace_detect_autocmd or features_enabled then
		return
	end
	workspace_detect_autocmd = vim.api.nvim_create_autocmd(WORKSPACE_EVENTS, {
		group = workspace_detect_group,
		callback = workspace_detection_callback,
	})
end

function UE.setup(opts)
	opts = opts or {}
	config.engine_path = opts.engine_path or config.engine_path
	config.auto_register_clangd = opts.auto_register_clangd or config.auto_register_clangd
	if opts.keymaps ~= nil then
		config.keymaps = opts.keymaps
	end
	-- Try to find the project on load.
	local uproj = utils.find_uproject()

	if config.auto_register_clangd and has_lspconfig and lspconfig.clangd then
		lspconfig.clangd.setup({
			cmd = {
				"clangd",
				"--background-index",
				"--clang-tidy",
				"--header-insertion=iwyu",
				"--completion-style=detailed",
			},
			on_attach = function(_, buf)
				vim.bo[buf].omnifunc = "v:lua.vim.lsp.omnifunc"
			end,
			root_dir = lspconfig.util.root_pattern("*.uproject", "compile_commands.json", ".git"),
			init_options = { compilationDatabasePath = ".", fallbackFlags = { "-std=c++17" } },
		})
		-- Add lsp workspace folders if a project is found.
		if uproj then
			local project_root = vim.fn.fnamemodify(uproj, ":h")
			vim.lsp.buf.add_workspace_folder(project_root)
			vim.notify("[Unreal] Added workspace folder: " .. project_root, vim.log.levels.INFO)
		end
	end

	if not enable_unreal_features(vim.fn.getcwd()) then
		schedule_workspace_detection()
	end
end

return UE
