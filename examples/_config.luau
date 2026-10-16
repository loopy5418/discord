--[[
	Settings shared by the example bots, from flags, the environment and a token file:

	    --token <token>        (or DISCORD_TOKEN, or a file named "token" in the working
	                            directory or next to the project / built program)
	    --guild <id>           register commands in one guild (instant updates)
	    --prefix <prefix>      prefix for text commands (default "!")
	    --port <port>          HTTP example port (default 8080)
	    --public-key <hex>     HTTP example public key (default: fetched from the application)
	    --debug                print gateway payloads
	    --debug-rest           print REST calls
]]

local fs = require("@sonata/fs")
local path = require("@sonata/path")
local process = require("@sonata/process")

local config = {}

export type Config = {
	token: string?,
	guild: string?,
	prefix: string,
	port: number,
	publicKey: string?,
	debug: boolean,
	debugRest: boolean,
	positional: { string },
}

local function readToken(file: string): string?
	if fs.isFile(file) then
		local ok, text = pcall(fs.readFile, file)
		if ok then
			local token = string.gsub(text, "^%s+", ""):gsub("%s+$", "")
			if token ~= "" then
				return token
			end
		end
	end
	return nil
end

function config.parse(argv: { string }?): Config
	local list = argv or args
	local out: Config = {
		prefix = "!",
		port = 8080,
		debug = false,
		debugRest = false,
		positional = {},
	}
	local i = 1
	while i <= #list do
		local a = list[i]
		local key, inline = string.match(a, "^%-%-([%w%-]+)=(.*)$")
		if key == nil then
			key = string.match(a, "^%-%-([%w%-]+)$")
		end
		local function value(): string
			if inline then
				return inline
			end
			i += 1
			local v = list[i]
			if v == nil then
				print(`--{key} needs a value`)
				process.exit(2)
			end
			return v
		end
		if key == "token" then
			out.token = value()
		elseif key == "guild" then
			out.guild = value()
		elseif key == "prefix" then
			out.prefix = value()
		elseif key == "port" then
			out.port = tonumber(value()) or 8080
		elseif key == "public-key" then
			out.publicKey = value()
		elseif key == "debug" then
			out.debug = true
		elseif key == "debug-rest" then
			out.debugRest = true
		elseif key then
			print(`unknown option --{key}`)
			process.exit(2)
		else
			table.insert(out.positional, a)
		end
		i += 1
	end

	out.token = out.token
		or process.env.DISCORD_TOKEN
		or readToken("token")
		or readToken(path.join(sonata.project.root, "token"))
	out.guild = out.guild or process.env.DISCORD_GUILD
	return out
end

-- the settings, exiting with a hint when there is no token
function config.require(argv: { string }?): Config
	local c = config.parse(argv)
	if c.token == nil then
		print("no token: pass --token <token>, set DISCORD_TOKEN, or put it in a file named \"token\"")
		process.exit(2)
	end
	return c
end

return config
