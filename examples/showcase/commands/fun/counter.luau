-- components v2 with inline button handlers: no customId or registered handler needed.
local Bot = require("../../../../lib") -- in your project: require("@discord")
local ui = Bot.ui

return {
	name = "counter",
	description = "A button counter",
	category = "Fun",
	run = function(ctx)
		local count = 0

		-- the handlers capture `count`, so each /counter has its own
		local function render()
			return {
				components = {
					ui.container({
						accent = if count >= 0 then "#57F287" else "#ED4245",
						ui.text(`# {count}`),
						ui.text(ctx.fmt.subtext(`started by {ctx:displayName()}`)),
						ui.row(
							ui.button({ label = "-1", style = "danger", run = function(c)
								count -= 1
								c:update(render())
							end }),
							ui.button({ label = "+1", style = "success", run = function(c)
								count += 1
								c:update(render())
							end }),
							ui.button({ label = "Reset", style = "secondary", run = function(c)
								count = 0
								c:update(render())
							end })
						),
					}),
				},
			}
		end
		ctx:reply(render())
	end,
}
