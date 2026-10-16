--[[
	Every feature, with commands, components and events loaded from folders.

	    sn run -- showcase --token <token> [--guild <id>]

	In a built program the folders are read from the assets listed in .sonata/project.luau.
]]

local discord = require("../../lib") -- in your project: require("@discord")
local config = require("../_config")

local cfg = config.require()

local bot = discord.new({
	token = cfg.token,
	prefix = cfg.prefix,
	-- MessageContent is privileged: enable it under Bot > Privileged Gateway Intents
	-- (without it the bot connects anyway and prefix commands only work in DMs and @mentions)
	intents = { "Guilds", "GuildMessages", "DirectMessages", "MessageContent" },
	-- register commands in one server while developing (instant updates)
	devGuild = cfg.guild,
	debug = cfg.debug,
	debugRest = cfg.debugRest,
})

-- commands, components and events live in their own folders
bot:load("commands", "components", "events")

-- you can also define things inline
bot:command({
	name = "uptime",
	description = "How long the bot has been running",
	prefix = true,
	run = function(ctx)
		ctx:reply(`Up since {ctx.fmt.timestamp(ctx.bot.startedAt, "R")}.`)
	end,
})

-- middleware wraps every command, component and modal
bot:use(function(ctx, next)
	if ctx.kind ~= "component" and ctx.kind ~= "modal" then
		print(`[{ctx.kind}] {ctx.user and ctx.user.username}: {ctx.commandPath}`)
	end
	next()
end)

bot:start()
return nil
