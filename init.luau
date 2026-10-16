--[[
	discord: a Discord bot framework for Sonata

	    local discord = require("@discord")

	    local bot = discord.new({ token = TOKEN, prefix = "!" })
	    bot:command({
	        name = "ping", description = "Pong!", prefix = true,
	        run = function(ctx) ctx:reply("Pong!") end,
	    })
	    bot:load("commands", "events")
	    bot:start()

	The library lives in lib/ (also reachable as require("@discord/lib/<module>")). See README.md.

	Run directly (`sn run`, or a program built from this project) it is the example launcher:

	    sn run -- whoami --token <token>
	    ./dist/discord showcase
]]

local discord = require("./lib")

export type Context = discord.Context
export type CommandDefinition = discord.CommandDefinition
export type ComponentDefinition = discord.ComponentDefinition
export type ModalDefinition = discord.ModalDefinition
export type EventDefinition = discord.EventDefinition
export type BotOptions = discord.BotOptions

if sonata.entry == debug.info(1, "s") then
	require("./examples/launcher").main(args)
end

return discord
