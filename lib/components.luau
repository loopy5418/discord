--[[
	Component builders (classic components, components v2, modals), embeds and polls

	Every builder returns a plain table in discord JSON shape, encode with `@sonata/json.encode`

	    local ui = require("@discord/lib/components")
	    ctx:reply({
	        components = {
	            ui.container({ accent = "#5865F2",
	                ui.text("# Hello"),
	                ui.section({ ui.text("Some text"), accessory = ui.thumbnail(avatarUrl) }),
	                ui.separator(),
	                ui.row(
	                    ui.button({ label = "Yes", style = "success", customId = "vote:yes" }),
	                    ui.button({ label = "Inline", run = function(ctx) ctx:update("clicked!") end })
	                ),
	            }),
	        },
	    })

	Messages that contain components v2 (anything but action rows at the top level) get the
	IsComponentsV2 flag automatically; such messages can't have `content` or `embeds`.

	A button, select or modal with a `run` function gets a generated custom id and its handler is
	kept for `ttl` seconds (default 15 minutes), so short-lived UIs need no registered handler.
]]

local crypto = require("@sonata/crypto")
local enums = require("./enums")

local T = enums.ComponentType

local ui = {}

-- inline handlers ----------------------------------------------------------------------------

local CALLBACK_PREFIX = "~cb:"
local callbacks: { [string]: { run: (...any) -> ...any, expires: number, once: boolean } } = {}
local lastSweep = 0

local function sweep()
	local now = os.time()
	if now - lastSweep < 60 then
		return
	end
	lastSweep = now
	for id, entry in callbacks do
		if entry.expires < now then
			callbacks[id] = nil
		end
	end
end

-- registers `run` and returns the custom id that triggers it
function ui.callback(run: (...any) -> ...any, ttl: number?, once: boolean?): string
	sweep()
	local id = CALLBACK_PREFIX .. crypto.randomBytes(9, "base64url")
	callbacks[id] = { run = run, expires = os.time() + (ttl or 900), once = once == true }
	return id
end

-- the handler for a custom id made by ui.callback, if it is still alive
function ui.findCallback(customId: string): ((...any) -> ...any)?
	if string.sub(customId, 1, #CALLBACK_PREFIX) ~= CALLBACK_PREFIX then
		return nil
	end
	local entry = callbacks[customId]
	if entry == nil or entry.expires < os.time() then
		callbacks[customId] = nil
		return nil
	end
	if entry.once then
		callbacks[customId] = nil
	end
	return entry.run
end

function ui.removeCallback(customId: string)
	callbacks[customId] = nil
end

-- helpers ------------------------------------------------------------------------------------

-- "#5865F2", "5865F2", 0x5865F2 or { r, g, b } -> number
function ui.color(value: any): number?
	if value == nil then
		return nil
	elseif type(value) == "number" then
		return value
	elseif type(value) == "table" then
		return (value[1] or 0) * 65536 + (value[2] or 0) * 256 + (value[3] or 0)
	end
	local hex = string.gsub(tostring(value), "^#", "")
	return tonumber(hex, 16)
end

-- "👍", "<:name:id>", "<a:name:id>", "name:id", an id or an emoji table -> partial emoji
function ui.emoji(value: any): any
	if value == nil or type(value) == "table" then
		return value
	end
	local animated, name, id = string.match(value, "^<(a?):([%w_]+):(%d+)>$")
	if id then
		return { id = id, name = name, animated = animated == "a" }
	end
	name, id = string.match(value, "^([%w_]+):(%d+)$")
	if id then
		return { id = id, name = name }
	end
	if string.match(value, "^%d+$") then
		return { id = value }
	end
	return { name = value }
end

-- the children of a builder table: its array part, or a `components` field
local function children(t: { [any]: any }): { any }
	if t.components then
		return t.components
	end
	local out = {}
	for _, child in ipairs(t) do
		table.insert(out, child)
	end
	return out
end

local function media(value: any): any
	if type(value) == "string" then
		return { url = value }
	end
	return value
end

local function withId(component: { [string]: any }, t: { [string]: any }?)
	-- `id` is an optional numeric identifier Discord echoes back, distinct from custom_id
	if t and type(t.id) == "number" then
		component.id = t.id
	end
	return component
end

local function customIdFor(t: { [string]: any }, kind: string): string
	if t.run then
		return ui.callback(t.run, t.ttl, t.once)
	end
	local id = t.customId or t.custom_id
	if id == nil then
		error(`{kind} needs a customId (or a run function)`, 3)
	end
	return id
end

-- layout -------------------------------------------------------------------------------------

-- ui.row(button, button) or ui.row({ button, button })
function ui.row(...: any): any
	local first = ...
	local list
	if select("#", ...) == 1 and type(first) == "table" and first.type == nil then
		list = children(first)
	else
		list = { ... }
	end
	return { type = T.ActionRow, components = list }
end

-- ui.container({ accent = "#hex", spoiler = false, ...children })
function ui.container(t: { [any]: any }): any
	local list = {}
	for _, child in children(t) do
		table.insert(list, if type(child) == "string" then ui.text(child) else child)
	end
	return withId({
		type = T.Container,
		components = ui.normalize(list),
		accent_color = ui.color(t.accent or t.accentColor or t.color),
		spoiler = t.spoiler,
	}, t)
end

-- ui.section({ ui.text("..."), accessory = ui.button(...) or ui.thumbnail(url) })
-- Strings in the array part become text displays.
function ui.section(t: { [any]: any }): any
	local list = {}
	for _, child in children(t) do
		table.insert(list, if type(child) == "string" then ui.text(child) else child)
	end
	return withId({
		type = T.Section,
		components = list,
		accessory = t.accessory,
	}, t)
end

-- ui.text("markdown") or ui.text({ content = "...", id = 1 })
function ui.text(content: any): any
	if type(content) == "table" then
		return withId({ type = T.TextDisplay, content = content.content or content[1] }, content)
	end
	return { type = T.TextDisplay, content = tostring(content) }
end

-- ui.thumbnail(url) or ui.thumbnail({ url = ..., description = ..., spoiler = ... })
function ui.thumbnail(t: any): any
	if type(t) == "string" then
		return { type = T.Thumbnail, media = { url = t } }
	end
	return withId({
		type = T.Thumbnail,
		media = media(t.url or t.media),
		description = t.description,
		spoiler = t.spoiler,
	}, t)
end

-- ui.gallery({ "url", { url = ..., description = ..., spoiler = true } })
function ui.gallery(t: { [any]: any }): any
	local items = {}
	for _, item in (t.items or children(t)) do
		if type(item) == "string" then
			table.insert(items, { media = { url = item } })
		else
			table.insert(items, {
				media = media(item.url or item.media),
				description = item.description,
				spoiler = item.spoiler,
			})
		end
	end
	return withId({ type = T.MediaGallery, items = items }, t)
end
ui.mediaGallery = ui.gallery

-- ui.file("attachment://report.pdf") — shows an uploaded file; upload it with `files`
function ui.file(t: any): any
	if type(t) == "string" then
		return { type = T.File, file = { url = t } }
	end
	return withId({ type = T.File, file = media(t.url or t.file), spoiler = t.spoiler }, t)
end

-- ui.separator() or ui.separator({ divider = false, spacing = "large" })
function ui.separator(t: { [string]: any }?): any
	local tTP = t or {} -- tTypeFix
	return withId({
		type = T.Separator,
		divider = if tTP.divider == nil then true else tTP.divider,
		spacing = enums.resolve(enums.SeparatorSpacing, tTP.spacing, "separator spacing"),
	}, t)
end

-- interactive --------------------------------------------------------------------------------

--[[
	ui.button({ label, style = "primary"|"secondary"|"success"|"danger"|"link"|"premium",
	            customId | url | skuId | run, emoji, disabled })
]]
function ui.button(t: { [string]: any }): any
	local style = enums.resolve(enums.ButtonStyle, t.style, "button style")
	if style == nil then
		style = if t.url then enums.ButtonStyle.Link
			elseif t.skuId then enums.ButtonStyle.Premium
			else enums.ButtonStyle.Primary
	end
	local button: { [string]: any } = {
		type = T.Button,
		style = style,
		label = t.label,
		emoji = ui.emoji(t.emoji),
		disabled = t.disabled,
	}
	if style == enums.ButtonStyle.Link then
		button.url = t.url or error("link buttons need a url", 2)
	elseif style == enums.ButtonStyle.Premium then
		button.sku_id = t.skuId or error("premium buttons need a skuId", 2)
	else
		button.custom_id = customIdFor(t, "button")
	end
	return withId(button, t)
end

-- shorthand for a link button
function ui.link(label: string, url: string, emoji: any?): any
	return ui.button({ label = label, url = url, emoji = emoji })
end

-- ui.option("Label", "value", { description, emoji, default }) for string selects
function ui.option(label: string, value: string?, extra: { [string]: any }?): any
	local extraTP = extra or {} -- extraTypeFix
	return {
		label = label,
		value = value or label,
		description = extraTP.description,
		emoji = ui.emoji(extraTP.emoji),
		default = extraTP.default,
	}
end

local function selectBase(kind: number, t: { [string]: any }, name: string)
	return withId({
		type = kind,
		custom_id = customIdFor(t, name),
		placeholder = t.placeholder,
		min_values = t.min or t.minValues,
		max_values = t.max or t.maxValues,
		disabled = t.disabled,
		required = t.required, -- in modals
	}, t)
end

-- ui.select({ customId, placeholder, min, max, options = { "a", ui.option("B", "b"), { label, value } } })
function ui.select(t: { [string]: any }): any
	local s = selectBase(T.StringSelect, t, "select")
	local options = {}
	for _, o in t.options or {} do
		if type(o) == "string" then
			table.insert(options, ui.option(o, o))
		else
			table.insert(options, {
				label = o.label,
				value = o.value or o.label,
				description = o.description,
				emoji = ui.emoji(o.emoji),
				default = o.default,
			})
		end
	end
	s.options = options
	return s
end
ui.stringSelect = ui.select

-- default values: ids, or { id, type = "user"|"role"|"channel" }
local function defaults(list: { any }?, defaultType: string): { any }?
	if list == nil then
		return nil
	end
	local out = {}
	for _, v in list do
		if type(v) == "table" then
			table.insert(out, { id = v.id, type = v.type or defaultType })
		else
			table.insert(out, { id = tostring(v), type = defaultType })
		end
	end
	return out
end

function ui.userSelect(t: { [string]: any }): any
	local s = selectBase(T.UserSelect, t, "user select")
	s.default_values = defaults(t.defaults or t.defaultValues, "user")
	return s
end

function ui.roleSelect(t: { [string]: any }): any
	local s = selectBase(T.RoleSelect, t, "role select")
	s.default_values = defaults(t.defaults or t.defaultValues, "role")
	return s
end

function ui.mentionableSelect(t: { [string]: any }): any
	local s = selectBase(T.MentionableSelect, t, "mentionable select")
	s.default_values = defaults(t.defaults or t.defaultValues, "user")
	return s
end

-- channelTypes: names ("text", "voice", "thread", ...) or numbers, see enums.ChannelTypeAlias
function ui.channelSelect(t: { [string]: any }): any
	local s = selectBase(T.ChannelSelect, t, "channel select")
	s.default_values = defaults(t.defaults or t.defaultValues, "channel")
	if t.channelTypes then
		local types = {}
		for _, ct in t.channelTypes do
			table.insert(types, if type(ct) == "number" then ct else enums.ChannelTypeAlias[ct] or error(`unknown channel type "{ct}"`, 2))
		end
		s.channel_types = types
	end
	return s
end

-- modal parts --------------------------------------------------------------------------------

-- ui.textInput({ customId, style = "short"|"paragraph", placeholder, value, minLength, maxLength, required })
function ui.textInput(t: { [string]: any }): any
	return withId({
		type = T.TextInput,
		custom_id = t.customId or t.custom_id or error("text inputs need a customId", 2),
		style = enums.resolve(enums.TextInputStyle, t.style or "short", "text input style"),
		placeholder = t.placeholder,
		value = t.value,
		min_length = t.minLength,
		max_length = t.maxLength,
		required = t.required,
		-- the old label field is only used in action rows; prefer ui.label
		label = t.label,
	}, t)
end

-- wraps a modal input with a label and description:
-- ui.label({ label = "Name", description = "...", component = ui.textInput(...) })
function ui.label(t: { [string]: any }): any
	local component = t.component
	if component and component.type == T.TextInput then
		component.label = nil
	end
	return withId({
		type = T.Label,
		label = t.label,
		description = t.description,
		component = component,
	}, t)
end

-- ui.fileUpload({ customId, min, max, required })
function ui.fileUpload(t: { [string]: any }): any
	return withId({
		type = T.FileUpload,
		custom_id = t.customId or t.custom_id or error("file uploads need a customId", 2),
		min_values = t.min or t.minValues,
		max_values = t.max or t.maxValues,
		required = t.required,
	}, t)
end

local function choiceOptions(list: { any }?): { any }
	local out = {}
	local items: { any } = list or {}
	for _, o in items do
		if type(o) == "string" then
			table.insert(out, { label = o, value = o })
		else
			table.insert(out, { label = o.label, value = o.value or o.label, description = o.description, default = o.default })
		end
	end
	return out
end

-- ui.radioGroup({ customId, options = { "a", { label, value, description, default } }, required })
function ui.radioGroup(t: { [string]: any }): any
	return withId({
		type = T.RadioGroup,
		custom_id = t.customId or t.custom_id or error("radio groups need a customId", 2),
		options = choiceOptions(t.options),
		required = t.required,
	}, t)
end

-- ui.checkboxGroup({ customId, options, min, max, required })
function ui.checkboxGroup(t: { [string]: any }): any
	return withId({
		type = T.CheckboxGroup,
		custom_id = t.customId or t.custom_id or error("checkbox groups need a customId", 2),
		options = choiceOptions(t.options),
		min_values = t.min or t.minValues,
		max_values = t.max or t.maxValues,
		required = t.required,
	}, t)
end

-- ui.checkbox({ customId, default = false })
function ui.checkbox(t: { [string]: any }): any
	return withId({
		type = T.Checkbox,
		custom_id = t.customId or t.custom_id or error("checkboxes need a customId", 2),
		default = t.default,
	}, t)
end

--[[
	ui.modal({ title, customId | run, ...components })

	Inputs that aren't wrapped are wrapped for you: a text input with a `label` becomes a
	ui.label, so `ui.textInput({ customId = "name", label = "Name" })` works directly.
]]
function ui.modal(t: { [any]: any }): any
	local list = {}
	for _, c in children(t) do
		if c.type == T.TextInput or c.type == T.StringSelect or c.type == T.UserSelect or c.type == T.RoleSelect
			or c.type == T.MentionableSelect or c.type == T.ChannelSelect or c.type == T.FileUpload
			or c.type == T.RadioGroup or c.type == T.CheckboxGroup or c.type == T.Checkbox
		then
			local label = c.label or c.custom_id
			c.label = nil
			table.insert(list, { type = T.Label, label = label, component = c })
		else
			table.insert(list, c)
		end
	end
	local customId
	if t.run then
		customId = ui.callback(t.run, t.ttl, true)
	else
		customId = t.customId or t.custom_id or ("~modal:" .. crypto.randomBytes(9, "base64url"))
	end
	return {
		title = t.title or "Form",
		custom_id = customId,
		components = list,
	}
end

-- embeds and polls ---------------------------------------------------------------------------

--[[
	ui.embed({ title, description, url, color, timestamp = true | unix seconds | iso string,
	           author = { name, url, icon } | "name", footer = { text, icon } | "text",
	           image = url, thumbnail = url, fields = { { name, value, inline } } })
]]
function ui.embed(t: { [string]: any }): any
	local embed: { [string]: any } = {
		title = t.title,
		description = t.description,
		url = t.url,
		color = ui.color(t.color),
	}
	if t.timestamp == true then
		embed.timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
	elseif type(t.timestamp) == "number" then
		embed.timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ", t.timestamp)
	elseif type(t.timestamp) == "string" then
		embed.timestamp = t.timestamp
	end
	if t.author then
		local a = if type(t.author) == "string" then { name = t.author } else t.author
		embed.author = { name = a.name, url = a.url, icon_url = a.icon or a.iconUrl or a.icon_url }
	end
	if t.footer then
		local f = if type(t.footer) == "string" then { text = t.footer } else t.footer
		embed.footer = { text = f.text, icon_url = f.icon or f.iconUrl or f.icon_url }
	end
	if t.image then
		embed.image = media(t.image)
	end
	if t.thumbnail then
		embed.thumbnail = media(t.thumbnail)
	end
	if t.fields then
		local fields = {}
		for _, f in t.fields do
			table.insert(fields, { name = f.name or f[1], value = f.value or f[2], inline = f.inline or f[3] })
		end
		embed.fields = fields
	end
	return embed
end

-- ui.poll({ question = "...", answers = { "A", { text = "B", emoji = "🐱" } }, duration = hours, multi = bool })
function ui.poll(t: { [string]: any }): any
	local answers = {}
	for _, a in t.answers or {} do
		if type(a) == "string" then
			table.insert(answers, { poll_media = { text = a } })
		else
			table.insert(answers, { poll_media = { text = a.text, emoji = ui.emoji(a.emoji) } })
		end
	end
	return {
		question = { text = t.question },
		answers = answers,
		duration = t.duration or 24,
		allow_multiselect = t.multi or t.allowMultiselect or false,
		layout_type = 1,
	}
end

-- utilities ----------------------------------------------------------------------------------

local LAYOUT_V2 = {
	[T.Section] = true,
	[T.TextDisplay] = true,
	[T.Thumbnail] = true,
	[T.MediaGallery] = true,
	[T.File] = true,
	[T.Separator] = true,
	[T.Container] = true,
}

-- whether a top-level component list needs the IsComponentsV2 flag
function ui.isV2(components: { any }?): boolean
	local componentsTF: { any } = components or {}
	for _, c in componentsTF do
		if type(c) == "table" and LAYOUT_V2[c.type] then
			return true
		end
	end
	return false
end

-- top-level buttons and selects aren't allowed: they are wrapped in action rows
function ui.normalize(components: { any }): { any }
	local out = {}
	local row = nil
	for _, c in components do
		local ty = if type(c) == "table" and type(c.type) == "number" then c.type else 0
		local interactive = ty == T.Button or (ty >= T.StringSelect and ty <= T.ChannelSelect and ty ~= T.TextInput)
		if interactive then
			-- selects take a whole row; buttons share one (max 5)
			if c.type ~= T.Button or row == nil or #row.components >= 5 or row.components[1].type ~= T.Button then
				row = { type = T.ActionRow, components = {} }
				table.insert(out, row)
			end
			table.insert(row.components, c)
			if c.type ~= T.Button then
				row = nil
			end
		else
			row = nil
			table.insert(out, c)
		end
	end
	return out
end

-- a deep copy with every button and select disabled, e.g. once a menu times out
function ui.disableAll(components: { any }): { any }
	local function copy(value: any): any
		if type(value) ~= "table" then
			return value
		end
		local out = {}
		for k, v in value do
			out[k] = copy(v)
		end
		if out.type == T.Button and out.style ~= enums.ButtonStyle.Link then
			out.disabled = true
		elseif type(out.type) == "number" and out.type >= T.StringSelect and out.type <= T.ChannelSelect and out.type ~= T.TextInput then
			out.disabled = true
		end
		return out
	end
	return copy(components)
end

-- finds a component (anywhere in a tree) by custom id
function ui.find(components: { any }, customId: string): any
	local componentsTF: { any } = components or {}
	for _, c in componentsTF do
		if c.custom_id == customId then
			return c
		end
		local found = (c.components and ui.find(c.components, customId))
			or (c.accessory and ui.find({ c.accessory }, customId))
			or (c.component and ui.find({ c.component }, customId))
		if found then
			return found
		end
	end
	return nil
end

return ui
