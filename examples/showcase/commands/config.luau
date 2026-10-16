-- subcommands and a subcommand group: /config show, /config prefix set <value>, /config prefix reset
-- (and !config show, !config prefix set ?, ...). Settings live in ctx.store for the demo.
return {
	name = "config",
	description = "Server settings",
	prefix = true,
	category = "Admin",
	guildOnly = true,
	permissions = { "ManageGuild" },
	subcommands = {
		{
			name = "show",
			description = "Show the current settings",
			run = function(ctx)
				local settings = ctx.store.settings and ctx.store.settings[ctx.guildId] or {}
				ctx:reply({ content = `Prefix: \`{settings.prefix or "!"}\``, ephemeral = true })
			end,
		},
		{
			name = "prefix",
			description = "The prefix for text commands",
			subcommands = {
				{
					name = "set",
					description = "Change the prefix",
					options = {
						{ name = "value", type = "string", description = "The new prefix", required = true, maxLength = 5 },
					},
					run = function(ctx, args)
						ctx.store.settings = ctx.store.settings or {}
						ctx.store.settings[ctx.guildId] = ctx.store.settings[ctx.guildId] or {}
						ctx.store.settings[ctx.guildId].prefix = args.value
						ctx:reply(`Prefix set to \`{args.value}\`.`)
					end,
				},
				{
					name = "reset",
					description = "Go back to the default prefix",
					run = function(ctx)
						local s = ctx.store.settings and ctx.store.settings[ctx.guildId]
						if s then
							s.prefix = nil
						end
						ctx:reply("Prefix reset to `!`.")
					end,
				},
			},
		},
	},
}
