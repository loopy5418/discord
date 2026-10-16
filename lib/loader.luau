--[[
	Loads bot parts (commands, components, modals, events, plugins) from files and folders

	    bot:load("commands")                 -- every .luau file under ./commands, recursively
	    bot:load("commands/ping.luau")       -- one file (the extension is optional)
	    bot:load("events", "components")     -- several at once
	    bot:load("plugins/*.luau")           -- glob patterns

	Relative paths are resolved from the file that calls `bot:load`, like `require`.

	In folders:
	- files and folders starting with `_` or `.` are skipped (use them for shared helpers)
	- a folder containing `init.luau` is loaded as one module, its other files aren't loaded
	- files load in sorted order, so `01-setup.luau` runs before `02-commands.luau`

	What a module can return is described in lib/init.luau (`Bot:add`).

	Built programs (`sn build`): every .luau file is compiled into the program, but there are no
	folders on disk to walk. Folders are listed from the program's assets instead, so add each
	folder you load to `build.assets` in your manifest:

	    build = { assets = { "commands", "events" } }

	By default the root project's assets are listed. A package that loads its own folders passes
	`assets = function(folder) return pocket.list(folder) end` to Bot.new, written in its own
	code (pocket answers for the package whose function calls it).
]]

local fs = require("@sonata/fs")
local path = require("@sonata/path")
local pocket = require("@sonata/pocket")

local loader = {}

-- require paths are relative to the file that calls require (this one)
local SELF_FILE = debug.info(1, "s")
local SELF_DIR = path.dirname(SELF_FILE)

local EXTENSIONS = { ".luau", ".lua" }

local function stripExtension(p: string): string
	for _, ext in EXTENSIONS do
		if string.sub(p, -#ext) == ext then
			return string.sub(p, 1, -#ext - 1)
		end
	end
	return p
end

local function hasExtension(p: string): boolean
	return stripExtension(p) ~= p
end

local function skipped(name: string): boolean
	local first = string.sub(name, 1, 1)
	return first == "_" or first == "."
end

local function initFile(dir: string): string?
	for _, ext in EXTENSIONS do
		local p = path.join(dir, "init" .. ext)
		if fs.isFile(p) then
			return p
		end
	end
	return nil
end

-- the directory of the script `level` frames above the caller
function loader.callerDir(level: number): string
	local source = debug.info(level + 1, "s")
	if source == nil or source == "" or string.sub(source, 1, 1) == "=" or string.sub(source, 1, 1) == "[" then
		return fs.cwd()
	end
	source = string.gsub(source, "^@", "")
	if sonata.bundled then
		return path.posix.dirname(source)
	end
	return path.dirname(path.resolve(source))
end

-- an absolute module path (file without extension, or a folder with init.luau) -> require path
function loader.requirePath(absolute: string): string
	local rel = if sonata.bundled
		then path.posix.relative(SELF_DIR, absolute)
		else path.toPosix(path.relative(SELF_DIR, absolute))
	if string.sub(rel, 1, 3) ~= "../" then
		rel = "./" .. rel
	end
	return rel
end

export type Lister = (folder: string) -> { string }

-- bundled: the root of the package a virtual path ("/commands/x.luau",
-- "/.sonata/deps/name/x.luau") belongs to
local function packageRoot(p: string): string
	local name = string.match(p, "^/%.sonata/deps/([^/]+)/")
	if name then
		return `/.sonata/deps/{name}/`
	end
	return "/"
end

-- the assets under `folder` (package-relative), through `lister` or the root project's assets.
-- pocket answers for the package of the function calling it; called from a fresh coroutine
-- there is no such function and it answers for the program's root project.
local function listAssets(folder: string, lister: Lister?): { string }
	if lister then
		return lister(folder)
	end
	local ok, result = pcall(coroutine.wrap(pocket.list), if folder == "" then nil else folder)
	if ok and type(result) == "table" then
		return result
	end
	return {}
end

-- requires an absolute path, with the file name in any error
function loader.require(absolute: string): any
	local target = stripExtension(absolute)
	local ok, result = pcall(require, loader.requirePath(target))
	if not ok then
		error(`failed to load {absolute}: {result}`, 0)
	end
	return result
end

--[[
	The files a target stands for, as { { file = absolute path, module = value } }, in order.
	`baseDir` resolves relative targets.
]]
function loader.collect(target: string, baseDir: string, lister: Lister?): { { file: string, module: any } }
	if sonata.bundled then
		return loader.collectBundled(target, baseDir, lister)
	end
	local results = {}
	local absolute = if path.isAbsolute(target) then target else path.resolve(baseDir, target)

	-- glob patterns
	if string.find(target, "[%*%?%[{]") then
		local matches = fs.glob(target, { cwd = baseDir, absolute = true })
		if #matches == 0 then
			print(`[loader] warning: "{target}" matched no files`)
		end
		for _, match in matches do
			if fs.isDir(match) then
				for _, r in loader.collect(match, baseDir, lister) do
					table.insert(results, r)
				end
			elseif hasExtension(match) and not skipped(path.basename(match)) then
				table.insert(results, { file = match, module = loader.require(match) })
			end
		end
		return results
	end

	if fs.isDir(absolute) then
		local init = initFile(absolute)
		if init then
			table.insert(results, { file = init, module = loader.require(absolute) })
			return results
		end
		local modules = {}
		for entry in fs.walk(absolute, {
			filter = function(e)
				if skipped(e.name) then
					return false
				end
				if e.kind == "directory" then
					local sub = initFile(e.fullPath)
					if sub then
						table.insert(modules, { sort = e.path, file = sub, target = e.fullPath })
						return false
					end
				end
				return true
			end,
		}) do
			if entry.kind == "file" and hasExtension(entry.name) then
				table.insert(modules, { sort = entry.path, file = entry.fullPath, target = entry.fullPath })
			end
		end
		table.sort(modules, function(a, b)
			return a.sort < b.sort
		end)
		for _, m in modules do
			table.insert(results, { file = m.file, module = loader.require(m.target) })
		end
		return results
	end

	-- a single file, with or without its extension
	if fs.isFile(absolute) then
		table.insert(results, { file = absolute, module = loader.require(absolute) })
		return results
	end
	for _, ext in EXTENSIONS do
		if fs.isFile(absolute .. ext) then
			table.insert(results, { file = absolute .. ext, module = loader.require(absolute .. ext) })
			return results
		end
	end
	error(`can't load "{target}": no such file or folder (looked in {baseDir})`, 0)
end

-- the same as collect, for built programs: folders come from the asset list
function loader.collectBundled(target: string, baseDir: string, lister: Lister?): { { file: string, module: any } }
	local results = {}
	local absolute = path.posix.normalize(if string.sub(target, 1, 1) == "/" then target else path.posix.join(baseDir, target))
	local root = packageRoot(absolute)
	local relative = string.sub(absolute, #root + 1)

	local function add(assetPath: string)
		local file = root .. assetPath
		table.insert(results, { file = file, module = loader.require(file) })
	end

	local function underFolder(folder: string): { string }
		local files = {}
		for _, asset in listAssets(folder, lister) do
			if hasExtension(asset) then
				table.insert(files, asset)
			end
		end
		return files
	end

	-- glob patterns: matched against every asset
	if string.find(target, "[%*%?%[{]") then
		for _, asset in underFolder("") do
			if fs.match(relative, asset) and not skipped(path.posix.basename(asset)) then
				add(asset)
			end
		end
		if #results == 0 then
			print(`[loader] warning: "{target}" matched no assets (bundled programs can only glob files listed in build.assets)`)
		end
		return results
	end

	-- a single file needs no asset entry: modules are compiled in
	if hasExtension(relative) then
		add(relative)
		return results
	end

	local files = underFolder(relative)
	if #files == 0 then
		-- not a listed folder; maybe a module named without its extension
		local ok, module = pcall(require, loader.requirePath(absolute))
		if ok then
			table.insert(results, { file = absolute, module = module })
			return results
		end
		error(`can't load "{target}" in this build: folders are read from the program's assets, so add "{relative}" to build.assets in .sonata/project.luau ({module})`, 0)
	end

	for _, ext in EXTENSIONS do
		if table.find(files, relative .. "/init" .. ext) then
			table.insert(results, { file = root .. relative .. "/init" .. ext, module = loader.require(root .. relative) })
			return results
		end
	end

	-- skip _names, and the contents of subfolders that have an init file
	table.sort(files)
	local modules = {}
	local initFolders = {}
	for _, asset in files do
		local inner = string.sub(asset, #relative + 2)
		local parts = string.split(inner, "/")
		local skip = false
		for _, part in parts do
			if skipped(part) then
				skip = true
			end
		end
		if not skip and #parts > 1 and string.match(parts[#parts], "^init%.") then
			local folder = relative .. "/" .. table.concat(parts, "/", 1, #parts - 1)
			initFolders[folder] = true
			table.insert(modules, { folder = folder, file = asset })
		elseif not skip then
			table.insert(modules, { file = asset })
		end
	end
	for _, m in modules do
		local insideInit = false
		for folder in initFolders do
			if m.folder ~= folder and string.sub(m.file, 1, #folder + 1) == folder .. "/" then
				insideInit = true
			end
		end
		if not insideInit then
			if m.folder then
				table.insert(results, { file = root .. m.file, module = loader.require(root .. m.folder) })
			else
				add(m.file)
			end
		end
	end
	return results
end

return loader
