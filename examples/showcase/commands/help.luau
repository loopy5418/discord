-- a help command built from bot:helpEntries(), shown with ctx:paginate (one page per category)
local Bot = require("../../../lib") -- in your project: require("@discord")
local ui = Bot.ui
local helpers = require("./_helpers")

return {
	name = "help",
	description = "List the commands",
	prefix = true,
	aliases = { "commands", "h" },
	options = {
		{ name = "command", type = "string", description = "A command to explain", autocomplete = function(ctx, typed)
			local out = {}
			for _, entry in ctx.bot:helpEntries() do
				if string.find(entry.name, string.lower(typed or ""), 1, true) then
					table.insert(out, entry.name)
				end
			end
			return out
		end },
	},
	run = function(ctx, args)
		local prefix = ctx.prefix or "!"
		local entries = ctx.bot:helpEntries(prefix)

		if args.command then
			for _, entry in entries do
				if entry.name == string.lower(args.command) or table.find(entry.aliases or {}, args.command) then
					return ctx:reply({
						embeds = { ui.embed({
							title = entry.name,
							description = entry.description,
							color = "#5865F2",
							fields = {
								{ "Usage", "`" .. entry.usage .. "`" },
								{ "Aliases", if #entry.aliases > 0 then table.concat(entry.aliases, ", ") else "none", true },
								{ "Category", entry.category, true },
							},
						}) },
					})
				end
			end
			return ctx:error(`No command called "{args.command}".`)
		end

		local pages = {}
		for _, group in helpers.groupBy(entries, "category") do
			local lines = {}
			for _, entry in group.items do
				local name = if entry.kind == "slash" then ctx:commandMention(entry.name) else `\`{entry.name}\``
				table.insert(lines, `{name} — {entry.description}`)
			end
			table.insert(pages, {
				components = {
					ui.container({
						accent = "#5865F2",
						ui.text(`## {group.key}`),
						ui.text(table.concat(lines, "\n")),
					}),
				},
			})
		end
		ctx:paginate(pages, { timeout = 90 })
	end,
}
