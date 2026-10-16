-- a module can return a list of definitions; events can use camelCase names
return {
	{
		event = "messageCreate",
		run = function(ctx, message)
			if message.author.bot then
				return
			end
			-- "hello bot" -> react
			if string.lower(message.content or "") == "hello bot" then
				ctx.api.channels.react(message.channel_id, message.id, "👋")
			end
		end,
	},
	{
		event = "GUILD_CREATE",
		run = function(ctx, guild)
			if ctx.bot.ready:isSet() then
				print(`joined {guild.name}`)
			end
		end,
	},
}
