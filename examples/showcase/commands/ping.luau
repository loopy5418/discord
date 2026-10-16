-- a hybrid command: /ping and !ping run the same code
return {
	name = "ping",
	description = "Check that the bot is alive",
	prefix = true,
	aliases = { "latency" },
	category = "Utility",
	run = function(ctx)
		local latency = ctx:latency()
		local shown = if latency then `{math.floor(latency * 1000)}ms` else "unknown"
		ctx:reply(`🏓 Pong! Gateway latency: **{shown}**`)
	end,
}
