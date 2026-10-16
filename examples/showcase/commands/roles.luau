-- sends a role picker; the select is handled in components/roles.luau by its custom id
local Bot = require("../../../lib") -- in your project: require("@discord")
local ui = Bot.ui

return {
	name = "rolepicker",
	description = "Post a self-assignable role menu",
	guildOnly = true,
	permissions = { "ManageRoles" },
	botPermissions = { "ManageRoles" },
	options = {
		{ name = "role1", type = "role", description = "A role people can pick", required = true },
		{ name = "role2", type = "role", description = "Another role" },
		{ name = "role3", type = "role", description = "Another role" },
	},
	run = function(ctx, args)
		local options = {}
		for _, key in { "role1", "role2", "role3" } do
			local role = args[key]
			if role then
				table.insert(options, ui.option(role.name, role.id))
			end
		end
		ctx:send({
			components = {
				ui.container({
					ui.text("## Pick your roles"),
					ui.text("Select the roles you want; deselect to remove them."),
					ui.select({
						-- "roles" picks the handler; the rest of the id is passed to it
						customId = "roles:pick",
						placeholder = "Choose roles",
						min = 0,
						max = #options,
						options = options,
					}),
				}),
			},
		})
		ctx:reply({ content = "Role menu posted.", ephemeral = true })
	end,
}
