-- prefix-only command with a cooldown
return {
	name = "purge",
	type = "prefix",
	description = "Delete recent messages",
	category = "Moderation",
	permissions = { "ManageMessages" },
	botPermissions = { "ManageMessages", "ReadMessageHistory" },
	cooldown = { seconds = 10, scope = "channel" },
	options = {
		{ name = "amount", type = "integer", description = "How many (2-100)", required = true, min = 2, max = 100 },
	},
	run = function(ctx, args)
		local list = ctx.api.channels.messages(ctx.channelId, { limit = args.amount, before = ctx.message.id })
		if list == nil then
			return ctx:reply("Couldn't read the channel.")
		end
		local ids = {}
		for _, m in list do
			table.insert(ids, m.id)
		end
		if #ids >= 2 then
			ctx.api.channels.bulkDelete(ctx.channelId, ids, `purge by {ctx.user.username}`)
		end
		local note = ctx:reply(`🧹 Deleted {#ids} message(s).`)
		ctx:sleep(3)
		if note then
			ctx.api.channels.deleteMessage(ctx.channelId, note.id)
		end
		ctx.api.channels.deleteMessage(ctx.channelId, ctx.message.id)
	end,
}
