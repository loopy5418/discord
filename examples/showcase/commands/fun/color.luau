-- autocomplete (a static list filtered as you type, and a function) and embeds
local Bot = require("../../../../lib") -- in your project: require("@discord")
local ui = Bot.ui

local COLORS = {
	red = "#ED4245",
	green = "#57F287",
	blue = "#5865F2",
	yellow = "#FEE75C",
	fuchsia = "#EB459E",
	white = "#FFFFFF",
	black = "#23272A",
}

local names = {}
for name in COLORS do
	table.insert(names, name)
end
table.sort(names)

return {
	name = "color",
	description = "Show a color",
	prefix = true,
	category = "Fun",
	options = {
		{
			name = "name",
			type = "string",
			description = "A color name",
			required = true,
			autocomplete = names, -- filtered by what the user typed
		},
		{
			name = "shade",
			type = "string",
			description = "Lighter or darker",
			autocomplete = function(ctx, typed)
				-- ctx.options has the other options typed so far
				return { `{ctx.options.name or "?"} (light)`, `{ctx.options.name or "?"} (dark)` }
			end,
		},
	},
	run = function(ctx, args)
		local hex = COLORS[string.lower(args.name)]
		if hex == nil then
			return ctx:error(`I don't know "{args.name}". Try one of: {table.concat(names, ", ")}`)
		end
		ctx:reply({
			embeds = {
				ui.embed({
					title = args.name,
					description = `Hex: \`{hex}\`` .. (if args.shade then `\nShade: {args.shade}` else ""),
					color = hex,
					footer = { text = "Colors!" },
					timestamp = true,
				}),
			},
		})
	end,
}
