--[[
	Command definitions: validation, the JSON Discord registers, option resolution for slash
	commands, and argument parsing for prefix commands.

	A definition (see types.luau for every field):

	    {
	        name = "ban", description = "Ban someone",
	        type = "slash",                -- "slash" (default) | "user" | "message" | "prefix"
	        prefix = true,                 -- also answer to !ban (slash commands)
	        aliases = { "b" },             -- prefix names
	        options = {
	            { name = "user", type = "user", description = "Who", required = true },
	            { name = "reason", type = "string", description = "Why" },
	        },
	        permissions = { "BanMembers" }, botPermissions = { "BanMembers" },
	        run = function(ctx, args) ... end,
	    }
]]

local enums = require("./enums")
local Permissions = require("./permissions")

local OT = enums.OptionType

local commands = {}

-- option type names -> Discord option types. "member" registers as a user option but
-- resolves to the guild member.
local OPTION_TYPES = {
	string = OT.String,
	str = OT.String,
	text = OT.String,
	integer = OT.Integer,
	int = OT.Integer,
	number = OT.Number,
	float = OT.Number,
	boolean = OT.Boolean,
	bool = OT.Boolean,
	user = OT.User,
	member = OT.User,
	channel = OT.Channel,
	role = OT.Role,
	mentionable = OT.Mentionable,
	attachment = OT.Attachment,
	file = OT.Attachment,
}
commands.OptionTypes = OPTION_TYPES

-- aliases -> the canonical name stored as option.typeName
local CANONICAL = { str = "string", text = "string", int = "integer", float = "number", bool = "boolean", file = "attachment" }

local INSTALL = { guild = 0, server = 0, user = 1 }
local CONTEXTS = { guild = 0, server = 0, botdm = 1, dm = 1, privatechannel = 2, private = 2, group = 2 }

local DEFAULT_DESCRIPTION = "No description"

local function kindOf(def: any): string
	local t = def.type
	if t == nil or t == "slash" or t == "chat" or t == "chatInput" or t == 1 then
		return "slash"
	elseif t == "user" or t == 2 then
		return "user"
	elseif t == "message" or t == 3 then
		return "message"
	elseif t == "prefix" or t == "text" then
		return "prefix"
	end
	error(`command "{def.name}": unknown type "{t}" (use slash, user, message or prefix)`, 4)
end

local function checkSlashName(name: string, what: string)
	if #name < 1 or #name > 32 or string.lower(name) ~= name or string.find(name, "%s") then
		error(`{what} "{name}" must be 1-32 lowercase characters without spaces`, 5)
	end
end

local function normalizeOption(option: any, owner: string): any
	if type(option) ~= "table" or type(option.name) ~= "string" then
		error(`command "{owner}": every option needs a name`, 4)
	end
	local typeName = string.lower(tostring(option.type or "string"))
	local optionType = if type(option.type) == "number" then option.type else OPTION_TYPES[typeName]
	if optionType == nil then
		error(`command "{owner}": option "{option.name}" has unknown type "{option.type}"`, 4)
	end
	local o = table.clone(option)
	o.typeName = if type(option.type) == "number" then "raw" else (CANONICAL[typeName] or typeName)
	o.discordType = optionType
	o.description = o.description or DEFAULT_DESCRIPTION
	return o
end

local function normalizeOptions(list: { any }?, owner: string, slash: boolean): { any }
	local out = {}
	local seenOptional = false
	local items: { any } = list or {}
	for _, option in items do
		local o = normalizeOption(option, owner)
		if slash then
			checkSlashName(o.name, `option of "{owner}"`)
			-- Discord requires required options first
			if o.required and seenOptional then
				error(`command "{owner}": required option "{o.name}" must come before optional ones`, 3)
			end
		end
		if not o.required then
			seenOptional = true
		end
		table.insert(out, o)
	end
	return out
end

-- subcommands: entries with their own `subcommands` are groups
local function normalizeSubcommands(def: any, slash: boolean, depth: number): { [string]: any }?
	if def.subcommands == nil then
		return nil
	end
	local map = {}
	local order = {}
	for _, sub in def.subcommands do
		if type(sub.name) ~= "string" then
			error(`command "{def.name}": every subcommand needs a name`, 3)
		end
		if slash then
			checkSlashName(sub.name, `subcommand of "{def.name}"`)
		end
		local s = table.clone(sub)
		s.description = s.description or DEFAULT_DESCRIPTION
		s.parent = def
		if sub.subcommands then
			if depth >= 2 then
				error(`command "{def.name}": subcommand groups can't be nested deeper`, 3)
			end
			s.isGroup = true
			s.subcommandMap, s.subcommandOrder = normalizeSubcommands(s, slash, depth + 1)
		else
			s.options = normalizeOptions(sub.options, `{def.name} {sub.name}`, slash)
			if s.run == nil and def.run == nil then
				error(`command "{def.name}": subcommand "{sub.name}" needs a run function`, 3)
			end
		end
		map[string.lower(sub.name)] = s
		for _, alias in sub.aliases or {} do
			map[string.lower(alias)] = s
		end
		table.insert(order, s)
	end
	return map, order
end

local function list(value: any): { any }?
	if value == nil then
		return nil
	elseif type(value) == "table" then
		return value
	end
	return { value }
end

-- validates a definition and fills in defaults. `botOptions` gives defaults for every command.
function commands.normalize(def: any, botOptions: { [string]: any }?): any
	local botOptionsTF = botOptions or {} -- botOptionsTypeFix
	if type(def) ~= "table" then
		error("a command definition must be a table", 3)
	end
	if type(def.name) ~= "string" then
		error("a command needs a name", 3)
	end
	local kind = kindOf(def)
	local c = table.clone(def)
	c.kind = kind
	c.slash = kind == "slash" and def.slash ~= false
	c.isPrefix = kind == "prefix" or def.prefix == true or (kind == "slash" and def.slash == false)
	c.description = c.description or DEFAULT_DESCRIPTION

	if c.slash then
		checkSlashName(c.name, "slash command name")
	elseif kind == "user" or kind == "message" then
		if #c.name < 1 or #c.name > 32 then
			error(`context menu command "{c.name}" must have 1-32 characters`, 3)
		end
	end

	if c.subcommands then
		if def.options then
			error(`command "{c.name}": use options on the subcommands, not on a command with subcommands`, 3)
		end
		c.subcommandMap, c.subcommandOrder = normalizeSubcommands(c, c.slash, 1)
		c.options = {}
	else
		c.options = normalizeOptions(def.options, c.name, c.slash)
		if type(c.run) ~= "function" then
			error(`command "{c.name}" needs a run function`, 3)
		end
	end

	if kind == "user" or kind == "message" then
		if #c.options > 0 or c.subcommands then
			error(`context menu command "{c.name}" can't have options or subcommands`, 3)
		end
	end

	-- `guildOnly` is shorthand for contexts = { "guild" }
	if c.guildOnly and c.contexts == nil then
		c.contexts = { "guild" }
	end
	c.install = list(c.install) or botOptionsTF.defaultInstall
	c.contexts = list(c.contexts) or botOptionsTF.defaultContexts
	c.aliases = c.aliases or {}

	if type(c.cooldown) == "number" then
		c.cooldown = { seconds = c.cooldown, scope = "user" }
	end
	return c
end

-- JSON for an option list (recursing into subcommands)
local function optionJSON(o: any): any
	local out: { [string]: any } = {
		type = o.discordType,
		name = o.name,
		description = o.description,
		required = o.required or nil,
		name_localizations = o.nameLocalizations,
		description_localizations = o.descriptionLocalizations,
		min_value = o.min or o.minValue,
		max_value = o.max or o.maxValue,
		min_length = o.minLength,
		max_length = o.maxLength,
	}
	if o.autocomplete then
		out.autocomplete = true
	end
	if o.choices then
		local choices = {}
		for _, choice in o.choices do
			if type(choice) == "table" then
				table.insert(choices, {
					name = choice.name or tostring(choice.value),
					value = choice.value,
					name_localizations = choice.nameLocalizations,
				})
			else
				table.insert(choices, { name = tostring(choice), value = choice })
			end
		end
		out.choices = choices
	end
	if o.channelTypes then
		local types = {}
		for _, ct in o.channelTypes do
			table.insert(types, if type(ct) == "number" then ct else enums.ChannelTypeAlias[ct] or error(`unknown channel type "{ct}"`))
		end
		out.channel_types = types
	end
	return out
end

local function subcommandJSON(sub: any): any
	if sub.isGroup then
		local options = {}
		for _, s in sub.subcommandOrder do
			table.insert(options, subcommandJSON(s))
		end
		return {
			type = OT.SubCommandGroup,
			name = sub.name,
			description = sub.description,
			name_localizations = sub.nameLocalizations,
			description_localizations = sub.descriptionLocalizations,
			options = options,
		}
	end
	local options = {}
	for _, o in sub.options do
		table.insert(options, optionJSON(o))
	end
	return {
		type = OT.SubCommand,
		name = sub.name,
		description = sub.description,
		name_localizations = sub.nameLocalizations,
		description_localizations = sub.descriptionLocalizations,
		options = options,
	}
end

local function mapNames(values: { any }?, map: { [string]: number }, what: string): { number }?
	if values == nil then
		return nil
	end
	local out = {}
	for _, v in values do
		if type(v) == "number" then
			table.insert(out, v)
		else
			local n = map[string.lower((string.gsub(tostring(v), "[%s_%-]", "")))]
			if n == nil then
				error(`unknown {what} "{v}"`, 4)
			end
			table.insert(out, n)
		end
	end
	return out
end

-- the application command object Discord registers, or nil for prefix-only commands
function commands.toJSON(c: any): any
	if c.kind == "prefix" or (c.kind == "slash" and not c.slash) then
		return nil
	end
	local out: { [string]: any } = {
		name = c.name,
		type = if c.kind == "user" then 2 elseif c.kind == "message" then 3 else 1,
		name_localizations = c.nameLocalizations,
		nsfw = c.nsfw or nil,
		integration_types = mapNames(c.install, INSTALL, "install type"),
		contexts = mapNames(c.contexts, CONTEXTS, "context"),
	}
	if c.kind == "slash" then
		out.description = c.description
		out.description_localizations = c.descriptionLocalizations
		local options = {}
		if c.subcommandOrder then
			for _, s in c.subcommandOrder do
				table.insert(options, subcommandJSON(s))
			end
		else
			for _, o in c.options do
				table.insert(options, optionJSON(o))
			end
		end
		out.options = options
	end
	if c.permissions then
		out.default_member_permissions = Permissions.toString(Permissions.resolve(c.permissions))
	end
	return out
end

-- slash commands -----------------------------------------------------------------------------

--[[
	Walks an interaction's data to the subcommand being run. Returns the leaf definition
	(command or subcommand), its path ("config set"), the leaf's raw options, and the group and
	subcommand names.
]]
function commands.resolveLeaf(c: any, data: any): (any, string, { any }, string?, string?)
	local leaf = c
	local options = data.options or {}
	local path = { c.name }
	local group, subcommand
	if c.subcommandMap then
		local first = options[1]
		if first and first.type == OT.SubCommandGroup then
			group = first.name
			table.insert(path, first.name)
			leaf = c.subcommandMap[string.lower(first.name)]
			options = first.options or {}
			first = options[1]
		end
		if first and first.type == OT.SubCommand and leaf and leaf.subcommandMap then
			subcommand = first.name
			table.insert(path, first.name)
			leaf = leaf.subcommandMap[string.lower(first.name)]
			options = first.options or {}
		elseif first and first.type == OT.SubCommand then
			subcommand = first.name
			table.insert(path, first.name)
			leaf = c.subcommandMap[string.lower(first.name)]
			options = first.options or {}
		end
	end
	return leaf, table.concat(path, " "), options, group, subcommand
end

-- turns raw interaction options into values: users, members, channels, roles and
-- attachments become their resolved objects. Returns the values and the focused option.
function commands.resolveOptions(leafOptions: { any }?, raw: { any }, resolved: any?): ({ [string]: any }, any?)
	resolved = resolved or {}
	local defs = {}
	local leaf: { any } = leafOptions or {}
	for _, o in leaf do
		defs[o.name] = o
	end
	local values = {}
	local focused = nil
	for _, option in raw do
		local def = defs[option.name]
		local value = option.value
		local t = option.type
		if option.focused then
			focused = { name = option.name, value = value, type = t, definition = def }
		end
		if t == OT.User or t == OT.Mentionable then
			local user = resolved.users and resolved.users[value]
			local member = resolved.members and resolved.members[value]
			local role = resolved.roles and resolved.roles[value]
			if user then
				if member then
					member = table.clone(member)
					member.user = user
				end
				if def and def.typeName == "member" then
					value = member
				else
					value = table.clone(user)
					value.member = member
				end
			elseif role then
				value = role
			end
		elseif t == OT.Channel then
			value = (resolved.channels and resolved.channels[value]) or { id = value }
		elseif t == OT.Role then
			value = (resolved.roles and resolved.roles[value]) or { id = value }
		elseif t == OT.Attachment then
			value = (resolved.attachments and resolved.attachments[value]) or { id = value }
		end
		values[option.name] = value
	end
	-- defaults for options the user left out
	for name, def in defs do
		if values[name] == nil and def.default ~= nil then
			values[name] = def.default
		end
	end
	return values, focused
end

-- prefix commands ----------------------------------------------------------------------------

export type Token = { value: string, start: number, stop: number }

local QUOTES = { ['"'] = '"', ["'"] = "'", ["\u{201C}"] = "\u{201D}", ["\u{2018}"] = "\u{2019}" }

-- splits text into words, keeping "quoted strings" together; each token knows where it starts
-- so "the rest of the text" can be taken verbatim
function commands.tokenize(text: string): { Token }
	local tokens = {}
	local i = 1
	local n = #text
	while i <= n do
		local s, e = string.find(text, "^%s+", i)
		if s then
			i = e + 1
			if i > n then
				break
			end
		end
		local start = i
		local opened = nil
		for open, close in QUOTES do
			if string.sub(text, i, i + #open - 1) == open then
				opened = { open, close }
				break
			end
		end
		if opened then
			local from = i + #opened[1]
			local closeAt = string.find(text, opened[2], from, true)
			if closeAt then
				table.insert(tokens, { value = string.sub(text, from, closeAt - 1), start = start, stop = closeAt + #opened[2] - 1 })
				i = closeAt + #opened[2]
				continue
			end
		end
		local ws = string.find(text, "%s", i) or (n + 1)
		table.insert(tokens, { value = string.sub(text, i, ws - 1), start = start, stop = ws - 1 })
		i = ws
	end
	return tokens
end

local TRUE = { ["true"] = true, yes = true, y = true, on = true, ["1"] = true, enable = true, enabled = true }
local FALSE = { ["false"] = true, no = true, n = true, off = true, ["0"] = true, disable = true, disabled = true }

-- "<prefix><name> <usage>"
function commands.usage(c: any, prefix: string?, path: string?): string
	local parts = { (prefix or "") .. (path or c.name) }
	if c.subcommandOrder then
		local names = {}
		for _, s in c.subcommandOrder do
			table.insert(names, s.name)
		end
		table.insert(parts, "<" .. table.concat(names, "|") .. ">")
	end
	for i, o in c.options or {} do
		local name = o.name
		if o.typeName == "attachment" then
			name ..= " (attachment)"
		elseif commands.takesRest(c.options, i) then
			name ..= "..."
		end
		table.insert(parts, if o.required then `<{name}>` else `[{name}]`)
	end
	return table.concat(parts, " ")
end

-- whether option i swallows the rest of the text: options marked `rest = true`, and the last
-- string option unless it says `rest = false`
function commands.takesRest(options: { any }, i: number): boolean
	local o = options[i]
	if o.rest ~= nil then
		return o.rest
	end
	if o.typeName ~= "string" then
		return false
	end
	for j = i + 1, #options do
		if options[j].typeName ~= "attachment" then
			return false
		end
	end
	return true
end

local function choiceValue(def: any, raw: string): (any, string?)
	if def.choices == nil then
		return raw, nil
	end
	local names = {}
	for _, choice in def.choices do
		local name = if type(choice) == "table" then choice.name or tostring(choice.value) else tostring(choice)
		local value = if type(choice) == "table" then choice.value else choice
		if string.lower(name) == string.lower(raw) or string.lower(tostring(value)) == string.lower(raw) then
			return value, nil
		end
		table.insert(names, name)
	end
	return nil, `must be one of: {table.concat(names, ", ")}`
end

--[[
	Parses one token for an option. `lookup` resolves mentions/ids: it has user(id),
	member(id), channel(id) and role(idOrName), each returning an object or nil (they may
	yield to fetch). Returns the value, or nil and a reason.
]]
local function parseValue(def: any, raw: string, lookup: any): (any, string?)
	local t = def.typeName
	if t == "string" or t == "raw" then
		local v, err = choiceValue(def, raw)
		if err then
			return nil, err
		end
		if type(v) == "string" then
			if def.minLength and #v < def.minLength then
				return nil, `must be at least {def.minLength} characters`
			elseif def.maxLength and #v > def.maxLength then
				return nil, `must be at most {def.maxLength} characters`
			end
		end
		return v, nil
	elseif t == "integer" or t == "number" then
		if def.choices then
			local v, err = choiceValue(def, raw)
			if err then
				return nil, err
			end
			return tonumber(v), nil
		end
		local n = tonumber(raw)
		if n == nil or (t == "integer" and n % 1 ~= 0) then
			return nil, if t == "integer" then "must be a whole number" else "must be a number"
		end
		local min, max = def.min or def.minValue, def.max or def.maxValue
		if min and n < min then
			return nil, `must be at least {min}`
		elseif max and n > max then
			return nil, `must be at most {max}`
		end
		return n, nil
	elseif t == "boolean" then
		local lower = string.lower(raw)
		if TRUE[lower] then
			return true, nil
		elseif FALSE[lower] then
			return false, nil
		end
		return nil, "must be yes or no"
	elseif t == "user" or t == "member" then
		local id = string.match(raw, "^<@!?(%d+)>$") or string.match(raw, "^(%d+)$")
		if id == nil then
			return nil, "must be a user mention or id"
		end
		local value = if t == "member" then lookup.member(id) else lookup.user(id)
		if value == nil then
			return nil, if t == "member" then "isn't a member of this server" else "isn't a user I can find"
		end
		return value, nil
	elseif t == "channel" then
		local id = string.match(raw, "^<#(%d+)>$") or string.match(raw, "^(%d+)$")
		if id == nil then
			return nil, "must be a channel mention or id"
		end
		local channel = lookup.channel(id)
		if channel == nil then
			return nil, "isn't a channel I can find"
		end
		if def.channelTypes then
			local ok = false
			for _, ct in def.channelTypes do
				local n = if type(ct) == "number" then ct else enums.ChannelTypeAlias[ct]
				if channel.type == n then
					ok = true
				end
			end
			if not ok then
				return nil, "is the wrong kind of channel"
			end
		end
		return channel, nil
	elseif t == "role" then
		local id = string.match(raw, "^<@&(%d+)>$") or raw
		local role = lookup.role(id)
		if role == nil then
			return nil, "isn't a role I can find"
		end
		return role, nil
	elseif t == "mentionable" then
		local roleId = string.match(raw, "^<@&(%d+)>$")
		if roleId then
			local role = lookup.role(roleId)
			return role, if role then nil else "isn't a role I can find"
		end
		local id = string.match(raw, "^<@!?(%d+)>$") or string.match(raw, "^(%d+)$")
		if id then
			local user = lookup.user(id)
			if user then
				return user, nil
			end
			local role = lookup.role(id)
			if role then
				return role, nil
			end
		end
		return nil, "must be a user or role"
	end
	return raw, nil
end

--[[
	Parses prefix arguments against a leaf's options. `text` is everything after the command
	name. Returns (values, nil) or (nil, error message).
]]
function commands.parseArgs(leaf: any, text: string, lookup: any, attachments: { any }?): ({ [string]: any }?, string?)
	local options = leaf.options or {}
	local tokens = commands.tokenize(text)
	local values = {}
	local index = 1
	local attachmentIndex = 1
	for i, def in options do
		local t = def.typeName
		if t == "attachment" then
			local a = attachments and attachments[attachmentIndex]
			attachmentIndex += 1
			if a == nil and def.required then
				return nil, `\`{def.name}\` is required: attach a file`
			end
			values[def.name] = a
			continue
		end
		local token = tokens[index]
		if token == nil then
			if def.required then
				return nil, `\`{def.name}\` is required`
			end
			values[def.name] = def.default
			continue
		end
		local raw = token.value
		local tokenIndex = index
		if commands.takesRest(options, i) then
			raw = string.gsub(string.sub(text, token.start), "%s+$", "")
			-- a single quoted token stays unquoted
			if #tokens == index then
				raw = token.value
			end
			index = #tokens + 1
		else
			index += 1
		end
		local value, err = parseValue(def, raw, lookup)
		if err then
			if not def.required and def.skip ~= false and t ~= "string" then
				-- optional typed options that don't match are skipped, so the token can fill the next one
				index = tokenIndex
				values[def.name] = def.default
				continue
			end
			return nil, `\`{def.name}\` {err}`
		end
		values[def.name] = value
	end
	return values, nil
end

return commands
