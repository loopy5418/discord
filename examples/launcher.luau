--[[
	Example launcher: what `sn run` (and a program built from this project) runs.

	    sn run -- <example> [options]
	    ./dist/discord <example> [options]

	Each example also runs on its own: sn run --entry examples/ping/main.luau -- --token ...
]]

local process = require("@sonata/process")

local EXAMPLES = {
	{ name = "whoami", module = "./whoami/main", about = "check a token: the bot, its application, intents, gateway limits, an invite link" },
	{ name = "ping", module = "./ping/main", about = "the smallest bot: /ping and !ping" },
	{ name = "showcase", module = "./showcase/main", about = "every feature, loaded from folders (commands, components v2, modals, ...)" },
	{ name = "http", module = "./http/main", about = "interactions over HTTP instead of the gateway (--port, --public-key)" },
	{ name = "selftest", module = "../tests/offline", about = "offline tests of the library; no token needed" },
}

local launcher = {}

local function usage()
	print("usage: <program> <example> [options]\n")
	print("examples:")
	for _, e in EXAMPLES do
		print(string.format("  %-10s %s", e.name, e.about))
	end
	print([[

options:
  --token <token>      bot token (or DISCORD_TOKEN, or a file named "token")
  --guild <id>         register commands in one guild for instant updates
  --prefix <prefix>    prefix for text commands (default "!")
  --port <port>        port for the http example (default 8080)
  --public-key <hex>   public key for the http example (default: fetched)
  --debug              print gateway payloads
  --debug-rest         print REST calls

with sn run, put the arguments after --:  sn run -- whoami --token ...]])
end

function launcher.main(argv: { string })
	if table.find(argv, "--help") or table.find(argv, "-h") then
		usage()
		process.exit(0)
	end
	local name = require("./_config").parse(argv).positional[1]
	if name == nil or name == "help" then
		usage()
		process.exit(if name == nil then 2 else 0)
	end
	for _, e in EXAMPLES do
		if e.name == name then
			require(e.module)
			return
		end
	end
	print(`unknown example "{name}"\n`)
	usage()
	process.exit(2)
end

return launcher
