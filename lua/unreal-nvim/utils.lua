local M = {}

local cached_engine_root
local cached_project_path

local function each_parent(start, fn)
	local dir = vim.loop.fs_realpath(start or vim.fn.getcwd()) or vim.fn.getcwd()
	while dir and dir ~= "" do
		local result = fn(dir)
		if result then
			return result
		end
		local parent = vim.fn.fnamemodify(dir, ":h")
		if parent == dir then
			break
		end
		dir = parent
	end
	return nil
end

local function has_engine_source(dir)
	local src = dir .. "/Engine/Source"
	return vim.loop.fs_stat(src) ~= nil
end

function M.find_uproject(start)
	if cached_project_path then
		return cached_project_path
	end
	local proj = each_parent(start, function(dir)
		local files = vim.fn.globpath(dir, "*.uproject", false, true)
		if #files > 0 then
			return files[1]
		end
	end)
	if proj then
		cached_project_path = proj
	end
	return proj
end

function M.find_engine_root(start)
	return each_parent(start, function(dir)
		if has_engine_source(dir) then
			return dir
		end
	end)
end

function M.is_valid_engine_path(path)
	return path and vim.loop.fs_stat(path .. "/Engine/Build/BatchFiles") ~= nil
end

function M.get_cached_engine_root()
	return cached_engine_root
end

function M.save_engine_path(path, uproj)
	cached_engine_root = path
	if uproj then
		local project_folder = vim.fn.fnamemodify(uproj, ":h")
		local file = project_folder .. "/.ueinfo"
		local fd = io.open(file, "w")
		if fd then
			fd:write("UEPath=" .. path)
			fd:close()
		end
	end
	return path
end

function M.is_unreal_workspace(start)
	return M.find_uproject(start) ~= nil or M.find_engine_root(start) ~= nil
end

return M
