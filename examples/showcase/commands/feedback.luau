-- modals: ctx:prompt opens one and waits for it, with labels, a select and a text area
local Bot = require("../../../lib") -- in your project: require("@discord")
local ui = Bot.ui

return {
	name = "feedback",
	description = "Send feedback to the developers",
	category = "Utility",
	install = { "guild", "user" },
	run = function(ctx)
		local submitted = ctx:prompt(ui.modal({
			title = "Feedback",
			ui.label({
				label = "What is it about?",
				component = ui.select({
					customId = "topic",
					options = { "Bug", "Idea", "Other" },
				}),
			}),
			ui.label({
				label = "Your feedback",
				description = "Be as detailed as you like",
				component = ui.textInput({ customId = "text", style = "paragraph", maxLength = 1000 }),
			}),
		}), 600)

		if submitted == nil then
			return -- they closed the modal or took too long
		end
		local topic = submitted.fields.topic and submitted.fields.topic[1] or "Other"
		ctx:log(`{ctx.user.username} [{topic}]: {submitted.fields.text}`)
		submitted:reply({ content = `Thanks! Your **{topic}** feedback was recorded.`, ephemeral = true })
	end,
}
