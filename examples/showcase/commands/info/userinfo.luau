-- one file, two commands: /userinfo [user] and right click a user > Apps > User Info.
-- The reply is built with components v2.
local Bot = require("../../../../lib") -- in your project: require("@discord")
local ui = Bot.ui
local fmt = Bot.fmt

local function card(ctx, user, member)
	local joined = if member and member.joined_at then member.joined_at else nil
	local lines = {
		`**Username:** {user.username}`,
		`**ID:** {fmt.code(user.id)}`,
		`**Created:** {fmt.timestamp(fmt.snowflakeTime(user.id), "R")}`,
	}
	if joined then
		table.insert(lines, `**Joined:** {joined}`)
	end
	if member and member.roles and #member.roles > 0 then
		local roles = {}
		for _, id in member.roles do
			table.insert(roles, fmt.role(id))
		end
		table.insert(lines, `**Roles:** {table.concat(roles, " ")}`)
	end
	return {
		components = {
			ui.container({
				accent = user.accent_color or "#5865F2",
				ui.section({
					ui.text(`## {fmt.displayName(user, member)}`),
					ui.text(table.concat(lines, "\n")),
					accessory = ui.thumbnail(fmt.avatar(user, 256)),
				}),
				ui.separator(),
				ui.text(fmt.subtext(`Requested by {ctx:displayName()}`)),
			}),
			ui.row(ui.link("Avatar", fmt.avatar(user, 1024))),
		},
		allowedMentions = false,
	}
end

return {
	Bot.command({
		name = "userinfo",
		description = "Show information about a user",
		prefix = true,
		aliases = { "whois", "ui" },
		category = "Info",
		install = { "guild", "user" },
		contexts = { "guild", "botDm", "privateChannel" },
		options = {
			{ name = "user", type = "user", description = "Who to look at (default: you)" },
		},
		run = function(ctx, args)
			local user = args.user or ctx.user
			local member = user.member or (if user.id == ctx.user.id then ctx.member else nil)
			if member == nil and ctx.isPrefix and ctx.inGuild then
				member = ctx:fetchMember(user.id)
			end
			ctx:reply(card(ctx, user, member))
		end,
	}),

	Bot.userCommand({
		name = "User Info",
		install = { "guild", "user" },
		contexts = { "guild", "botDm", "privateChannel" },
		ephemeral = true,
		run = function(ctx, target)
			ctx:reply(card(ctx, target, ctx.targetMember))
		end,
	}),
}
