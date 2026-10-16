--[[
	The smallest useful bot: /ping and !ping.

	    sn run -- ping --token <token> [--guild <id>]
]]

local discord = require("../../lib") -- in your project: require("@discord")
local config = require("../_config")

local cfg = config.require()

local bot = discord.new({
	token = cfg.token,
	prefix = cfg.prefix,
	-- MessageContent lets !ping work in servers; it's dropped with a warning if the
	-- developer portal hasn't enabled it
	intents = { "Guilds", "GuildMessages", "DirectMessages", "MessageContent" },
	devGuild = cfg.guild,
	debug = cfg.debug,
	debugRest = cfg.debugRest,
})

bot:command({
	name = "ping",
	description = "Check that the bot is alive",
	prefix = true,
	run = function(ctx)
		local latency = ctx:latency()
		ctx:reply(`🏓 Pong! ({if latency then math.floor(latency * 1000) .. "ms" else "no heartbeat yet"})`)
	end,
})

bot:once("READY", function(ctx, data)
	print(`ready as {data.user.username}: try /ping or {cfg.prefix}ping`)
	ctx.bot:setStatus("online", "/ping", "listening")
end)

bot:start()
return nil
