-- a message context menu command that works as a user-installed app too:
-- right click any message > Apps > Quote, even in servers the bot isn't in.
local Bot = require("../../../../lib") -- in your project: require("@discord")
local ui = Bot.ui
local fmt = Bot.fmt

return Bot.messageCommand({
	name = "Quote",
	install = { "guild", "user" },
	contexts = { "guild", "botDm", "privateChannel" },
	run = function(ctx, message)
		local text = message.content
		if text == nil or text == "" then
			return ctx:error("That message has no text to quote.")
		end
		local author = message.author
		ctx:reply({
			components = {
				ui.container({
					accent = "#FEE75C",
					ui.section({
						ui.text(fmt.quote(fmt.truncate(text, 3000))),
						ui.text(fmt.subtext(`— {fmt.displayName(author)}, {fmt.timestamp(fmt.snowflakeTime(message.id), "D")}`)),
						accessory = ui.thumbnail(fmt.avatar(author, 128)),
					}),
				}),
			},
			allowedMentions = false,
		})
		-- in a server where the bot is installed this could also react; with a user install
		-- the bot may not be there, so check first
		if ctx.botPresent then
			ctx:react("💬")
		end
	end,
})
