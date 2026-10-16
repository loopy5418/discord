-- handles every component whose custom id starts with "roles:" (see commands/roles.luau)
local Bot = require("../../../lib") -- in your project: require("@discord")

return Bot.component({
	customId = "roles",
	defer = "ephemeral",
	botPermissions = { "ManageRoles" },
	run = function(ctx, action)
		if action ~= "pick" then
			return
		end
		-- every role on offer is in the select's options
		local select = ctx:findComponent(ctx.customId)
		local offered = {}
		for _, option in select and select.options or {} do
			offered[option.value] = true
		end
		local chosen = {}
		for _, id in ctx.values do
			chosen[id] = true
		end

		local current = {}
		for _, id in ctx.member.roles do
			current[id] = true
		end
		local added, removed = 0, 0
		for id in offered do
			if chosen[id] and not current[id] then
				ctx.api.guilds.addRole(ctx.guildId, ctx.user.id, id, "role picker")
				added += 1
			elseif not chosen[id] and current[id] then
				ctx.api.guilds.removeRole(ctx.guildId, ctx.user.id, id, "role picker")
				removed += 1
			end
		end
		ctx:reply(`Done: {added} added, {removed} removed.`)
	end,
})
