return {
	event = "READY",
	once = true,
	run = function(ctx, data)
		print(`logged in as {data.user.username}, in {#data.guilds} guild(s)`)
		ctx.bot:setStatus("online", "/help", "listening")
	end,
}
