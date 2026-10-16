-- permissions, bot permissions, a confirmation prompt and audit log reasons
return {
	name = "ban",
	description = "Ban a member",
	prefix = true,
	category = "Moderation",
	guildOnly = true,
	permissions = { "BanMembers" },
	botPermissions = { "BanMembers" },
	options = {
		{ name = "user", type = "user", description = "Who to ban", required = true },
		{ name = "days", type = "integer", description = "Delete their messages from the last N days", min = 0, max = 7 },
		{ name = "reason", type = "string", description = "Why", maxLength = 400 },
	},
	run = function(ctx, args)
		local user = args.user
		if user.id == ctx.user.id then
			return ctx:error("You can't ban yourself.")
		end
		local reason = args.reason or "No reason given"
		local confirmed = ctx:confirm(`Ban **{user.username}**? Reason: {reason}`, { ephemeral = true })
		if not confirmed then
			return ctx:followUp({ content = "Cancelled.", ephemeral = true })
		end
		local ok, err = ctx.api.guilds.ban(ctx.guildId, user.id, {
			deleteMessageSeconds = (args.days or 0) * 86400,
			reason = `{ctx.user.username}: {reason}`,
		})
		if not ok then
			return ctx:followUp({ content = `Couldn't ban: {tostring(err)}`, ephemeral = true })
		end
		ctx:followUp(`🔨 Banned **{user.username}**.`)
	end,
}
