--[[
	Context: the first argument of every command, component, modal, autocomplete and event
	handler. 
	Provides helpers for interacting with *everything*.

	See types.luau (`Context`) for the full list of fields and methods.
]]

local task = require("@sonata/task")
local json = require("@sonata/json")
local crypto = require("@sonata/crypto")

local enums = require("./enums")
local ui = require("./components")
local fmt = require("./format")
local messages = require("./messages")
local Permissions = require("./permissions")

local CB = enums.CallbackType
local _CT = enums.ComponentType

local Context = {}
Context.__index = Context

-- constructors -------------------------------------------------------------------------------

local function base(bot: any, kind: string): any
	return setmetatable({
		bot = bot,
		api = bot.api,
		rest = bot.rest,
		cache = bot.cache,
		ui = ui,
		fmt = fmt,
		enums = enums,
		permissions = Permissions,
		store = bot.store,
		state = {},
		kind = kind,
		createdAt = os.time(),
		isInteraction = false,
		isPrefix = false,
		responded = false,
		deferred = false,
		replied = false,
	}, Context)
end

local function parseCustomId(customId: string): (string, { string })
	local params = {}
	local name = customId
	local first = string.find(customId, ":", 1, true)
	if first and string.sub(customId, 1, 1) ~= "~" then
		name = string.sub(customId, 1, first - 1)
		for part in string.gmatch(string.sub(customId, first + 1), "[^:]*") do
			table.insert(params, part)
		end
		-- gmatch yields a trailing empty match after the last part
		if #params > 0 and params[#params] == "" and string.sub(customId, -1) ~= ":" then
			table.remove(params)
		end
	end
	return name, params
end
Context.parseCustomId = parseCustomId

-- modal values by custom id: text inputs give strings, selects/uploads/checkbox groups lists,
-- checkboxes booleans
local function modalFields(components: { any }?): { [string]: any }
	local fields = {}
	local function visit(c: any)
		if c == nil then
			return
		end
		if c.custom_id then
			if c.value ~= nil then
				fields[c.custom_id] = c.value
			elseif c.values ~= nil then
				fields[c.custom_id] = c.values
			end
		end
		if c.component then
			visit(c.component)
		end
		for _, child in c.components or {} do
			visit(child)
		end
	end
	local componentsTF: { any } = components or {}
	for _, c in componentsTF do
		visit(c)
	end
	return fields
end

local CONTEXT_NAMES = { [0] = "guild", [1] = "botDm", [2] = "privateChannel" }

--[[
	A context for an interaction. `transport`, used for HTTP interactions, has
	`respond(body) -> boolean` for answering in the HTTP response.
]]
function Context.fromInteraction(bot: any, interaction: any, transport: any?): any
	local kind = "interaction"
	local t = interaction.type
	local data = interaction.data or {}
	if t == enums.InteractionType.ApplicationCommand then
		kind = if data.type == 2 then "user" elseif data.type == 3 then "message" else "slash"
	elseif t == enums.InteractionType.MessageComponent then
		kind = "component"
	elseif t == enums.InteractionType.Autocomplete then
		kind = "autocomplete"
	elseif t == enums.InteractionType.ModalSubmit then
		kind = "modal"
	end

	local ctx = base(bot, kind)
	ctx.isInteraction = true
	ctx._transport = transport
	ctx.interaction = interaction
	ctx.id = interaction.id
	ctx.token = interaction.token
	ctx.data = data

	local member = interaction.member
	local user = interaction.user or (member and member.user)
	ctx.user = user
	ctx.author = user
	ctx.member = member
	ctx.guildId = interaction.guild_id
	ctx.channelId = interaction.channel_id or (interaction.channel and interaction.channel.id)
	ctx.channel = interaction.channel -- partial channel sent with the interaction
	ctx.locale = interaction.locale
	ctx.guildLocale = interaction.guild_locale
	ctx.appPermissions = interaction.app_permissions
	ctx.entitlements = interaction.entitlements or {}
	ctx.message = interaction.message
	ctx.where = CONTEXT_NAMES[interaction.context or (if interaction.guild_id then 0 else 1)]
	ctx.inGuild = interaction.guild_id ~= nil
	ctx.inDM = not ctx.inGuild

	local owners = interaction.authorizing_integration_owners or {}
	ctx.authorizingOwners = owners
	ctx.isGuildInstall = owners["0"] ~= nil
	ctx.isUserInstall = owners["1"] ~= nil and owners["0"] == nil
	-- whether the bot itself is in this guild/channel and can use normal API calls there
	ctx.botPresent = ctx.inDM and ctx.where == "botDm" or (ctx.inGuild and owners["0"] ~= nil)
	if interaction.context == nil then
		ctx.botPresent = true
	end

	if kind == "component" then
		ctx.customId = data.custom_id
		ctx.componentType = data.component_type
		ctx.values = data.values or {}
		ctx.resolved = data.resolved
		ctx.name, ctx.params = parseCustomId(data.custom_id)
	elseif kind == "modal" then
		ctx.customId = data.custom_id
		ctx.fields = modalFields(data.components)
		ctx.resolved = data.resolved
		ctx.name, ctx.params = parseCustomId(data.custom_id)
	end
	return ctx
end

-- a context for a prefix command (or any message)
function Context.fromMessage(bot: any, message: any): any
	local ctx = base(bot, "prefix")
	ctx.isPrefix = true
	ctx.message = message
	ctx.user = message.author
	ctx.author = message.author
	if message.member then
		local member = table.clone(message.member)
		member.user = message.author
		ctx.member = member
	end
	ctx.guildId = message.guild_id
	ctx.channelId = message.channel_id
	ctx.content = message.content
	ctx.inGuild = message.guild_id ~= nil
	ctx.inDM = not ctx.inGuild
	ctx.where = if ctx.inGuild then "guild" else "botDm"
	ctx.botPresent = true
	ctx.isGuildInstall = ctx.inGuild
	ctx.isUserInstall = false
	return ctx
end

-- a context for a gateway event handler
function Context.forEvent(bot: any, event: string, data: any): any
	local ctx = base(bot, "event")
	ctx.event = event
	ctx.eventData = data
	if type(data) == "table" then
		ctx.guildId = data.guild_id
		ctx.channelId = data.channel_id
		if event == "MESSAGE_CREATE" or event == "MESSAGE_UPDATE" then
			ctx.message = data
			ctx.user = data.author
			ctx.author = data.author
			ctx.content = data.content
		elseif data.user then
			ctx.user = data.user
		end
		if data.member then
			ctx.member = data.member
		end
	end
	ctx.inGuild = ctx.guildId ~= nil
	ctx.inDM = not ctx.inGuild
	ctx.botPresent = true
	return ctx
end

-- internals ----------------------------------------------------------------------------------

function Context:_defaults(ephemeral: boolean?): { [string]: any }
	local e = ephemeral
	if e == nil then
		e = self.ephemeralDefault
	end
	return { ephemeral = e, allowedMentions = self.bot.options.allowedMentions }
end

function Context:_ephemeralOf(input: any): boolean?
	if type(input) == "table" and input.type == nil and input.ephemeral ~= nil then
		return input.ephemeral
	end
	return self.ephemeralDefault
end

-- sends the initial interaction response
function Context:_callback(callbackType: number, data: any?, files: { any }?): (any, any)
	if self.responded then
		return nil, "this interaction was already responded to"
	end
	self.responded = true
	local body = { type = callbackType, data = data }

	local transport = self._transport
	if transport and transport.open then
		if files == nil or #files == 0 then
			if transport.respond(body) then
				return true, nil
			end
		else
			-- files can't go in the HTTP response: defer there, then edit the original
			local deferType = if callbackType == CB.UpdateMessage then CB.DeferredUpdateMessage else CB.DeferredChannelMessageWithSource
			local flags = data and data.flags or 0
			local ephemeralBit = bit32.band(flags, enums.MessageFlags.Ephemeral)
			if transport.respond({ type = deferType, data = if ephemeralBit ~= 0 then { flags = ephemeralBit } else nil }) then
				local edit = table.clone(data or {})
				edit.flags = bit32.band(flags, bit32.bnot(enums.MessageFlags.Ephemeral))
				if edit.flags == 0 then
					edit.flags = nil
				end
				return self.rest:request("PATCH", `/webhooks/{self.bot.applicationId}/{self.token}/messages/@original`, {
					body = edit,
					files = files,
					auth = false,
				})
			end
		end
	end

	local withResponse = callbackType == CB.ChannelMessageWithSource or callbackType == CB.UpdateMessage
	local res, err = self.api.interactions.callback(self.id, self.token, body, files, withResponse)
	if res == nil then
		self.responded = false
		return nil, err
	end
	if type(res) == "table" and res.resource and res.resource.message then
		self.replyMessage = res.resource.message
		return res.resource.message, nil
	end
	return true, nil
end

local function checkInteraction(self: any, what: string)
	if not self.isInteraction then
		error(`ctx:{what}() is only available for interactions (this is a {self.kind} context)`, 3)
	end
end

-- the message to react to / reply to when a context isn't an interaction
local function targetMessage(self: any): any
	if self.kind == "message" and self.target then
		return self.target
	end
	return self.message
end

-- responding ---------------------------------------------------------------------------------

--[[
	Replies. Interactions: the first call is the response, after `defer` it fills in the deferred
	message, later calls send follow-ups. Prefix: replies to the command message.
	Returns the message (when Discord sends it back), or nil and an error.
]]
function Context:reply(input: any): (any, any)
	if self.isInteraction then
		if self.kind == "autocomplete" then
			error("autocomplete interactions can't reply; return choices or call ctx:respond(choices)", 2)
		end
		local ephemeral = self:_ephemeralOf(input)
		if not self.responded then
			local body, files = messages.build(input, self:_defaults(ephemeral))
			self.ephemeral = ephemeral == true
			local msg, err = self:_callback(CB.ChannelMessageWithSource, body, files)
			if msg then
				self.replied = true
			end
			return msg, err
		elseif self.deferred and not self.replied and not self.deferredUpdate then
			self.replied = true
			local msg, err = self.api.interactions.editOriginal(self.token, input)
			if msg then
				self.replyMessage = msg
			end
			return msg, err
		end
		return self:followUp(input)
	end

	local message = targetMessage(self)
	if message == nil then
		if self.channelId then
			return self:send(input)
		end
		error("this context has nothing to reply to", 2)
	end
	local body, files = messages.build(input, self:_defaults(false))
	body.flags = if body.flags then bit32.band(body.flags, bit32.bnot(enums.MessageFlags.Ephemeral)) else nil
	if body.flags == 0 then
		body.flags = nil
	end
	body.message_reference = { message_id = message.id, channel_id = message.channel_id, fail_if_not_exists = false }
	local msg, err = self.rest:request("POST", `/channels/{message.channel_id}/messages`, { body = body, files = files })
	if msg then
		self.replied = true
		self.responded = true
		if self.replyMessage == nil then
			self.replyMessage = msg
		end
	end
	return msg, err
end

-- a follow-up message (interactions), or another reply (prefix)
function Context:followUp(input: any): (any, any)
	if not self.isInteraction then
		return self:reply(input)
	end
	if not self.responded then
		return self:reply(input)
	end
	return self.api.interactions.followUp(self.token, input, self:_ephemeralOf(input))
end

--[[
	Acknowledges now and answers later (up to 15 minutes). Shows "thinking..." for commands.
	options: { ephemeral = bool }. For prefix commands it shows the typing indicator.
]]
function Context:defer(options: { ephemeral: boolean? }?): (any, any)
	if not self.isInteraction then
		return self:typing()
	end
	if self.responded then
		return true, nil
	end
	local ephemeral = if options and options.ephemeral ~= nil then options.ephemeral else self.ephemeralDefault
	self.ephemeral = ephemeral == true
	self.deferred = true
	local res, err = self:_callback(CB.DeferredChannelMessageWithSource, if ephemeral then { flags = enums.MessageFlags.Ephemeral } else nil)
	if res == nil then
		self.deferred = false
	end
	return res, err
end

-- components and modals: acknowledges without changing the message yet
function Context:deferUpdate(): (any, any)
	checkInteraction(self, "deferUpdate")
	if self.responded then
		return true, nil
	end
	self.deferred = true
	self.deferredUpdate = true
	local res, err = self:_callback(CB.DeferredUpdateMessage)
	if res == nil then
		self.deferred = false
		self.deferredUpdate = false
	end
	return res, err
end

--[[
	Components (and modals opened from a component): edits the message the component is on.
	Prefix: edits the bot's reply.
]]
function Context:update(input: any): (any, any)
	if not self.isInteraction then
		return self:edit(input)
	end
	if self.kind ~= "component" and self.kind ~= "modal" then
		return self:edit(input)
	end
	if not self.responded then
		local body, files = messages.build(input, self:_defaults(false), true)
		return self:_callback(CB.UpdateMessage, body, files)
	end
	return self.api.interactions.editOriginal(self.token, input)
end

-- edits the response (interactions) or the bot's first reply (prefix)
function Context:edit(input: any): (any, any)
	if self.isInteraction then
		if not self.responded then
			return nil, "nothing to edit yet: reply or defer first"
		end
		return self.api.interactions.editOriginal(self.token, input)
	end
	local reply = self.replyMessage
	if reply == nil then
		return self:reply(input)
	end
	return self.api.channels.editMessage(reply.channel_id, reply.id, input)
end
Context.editReply = Context.edit

function Context:deleteReply(): (any, any)
	if self.isInteraction then
		return self.api.interactions.deleteOriginal(self.token)
	end
	local reply = self.replyMessage
	if reply == nil then
		return nil, "no reply to delete"
	end
	self.replyMessage = nil
	return self.api.channels.deleteMessage(reply.channel_id, reply.id)
end

function Context:fetchReply(): (any, any)
	if self.isInteraction then
		local msg, err = self.api.interactions.getOriginal(self.token)
		if msg then
			self.replyMessage = msg
		end
		return msg, err
	end
	return self.replyMessage, nil
end

-- sends a normal message to the channel (not a reply). Needs the bot to be in the channel.
function Context:send(input: any): (any, any)
	if self.channelId == nil then
		return nil, "this context has no channel"
	end
	return self.api.channels.send(self.channelId, input)
end

--[[
	Opens a modal (slash/user/message commands and components only, as the first response).
	`modal` is a ui.modal(...) result, or a table ui.modal accepts.
]]
function Context:showModal(modal: any): (any, any)
	checkInteraction(self, "showModal")
	if modal.custom_id == nil then
		modal = ui.modal(modal)
	end
	return self:_callback(CB.Modal, modal)
end

--[[
	Opens a modal and waits for it to be submitted. Returns the modal's context (read
	`.fields`, then reply/update on it), or nil after `timeout` seconds (default 300).

	    local submitted = ctx:prompt(ui.modal({ title = "Feedback",
	        ui.textInput({ customId = "text", label = "Your feedback", style = "paragraph" }) }))
	    if submitted then submitted:reply("Thanks: " .. submitted.fields.text) end
]]
function Context:prompt(modal: any, timeout: number?): any
	checkInteraction(self, "prompt")
	if modal.custom_id == nil then
		local spec = table.clone(modal)
		spec.run = nil
		modal = ui.modal(spec)
	end
	local customId = modal.custom_id
	local userId = self.user and self.user.id
	local ch = task.channel()
	local handle = self.bot:_addCollector("modal", function(c)
		return c.customId == customId and (userId == nil or (c.user and c.user.id == userId))
	end, function(c)
		ch:trySend(c)
	end)
	local ok, err = self:showModal(modal)
	if not ok then
		handle:stop()
		self:log("prompt: couldn't show the modal:", tostring(err))
		return nil
	end
	local got, value = ch:recv(timeout or 300)
	handle:stop()
	return if got then value else nil
end

-- autocomplete: sends up to 25 choices (strings, numbers or { name, value })
function Context:respond(choices: { any }): (any, any)
	if self.kind ~= "autocomplete" then
		error("ctx:respond() is for autocomplete interactions", 2)
	end
	local out = {}
	for _, choice in choices do
		if #out >= 25 then
			break
		end
		if type(choice) == "table" then
			table.insert(out, { name = fmt.truncate(tostring(choice.name or choice.value), 100), value = choice.value or choice.name })
		else
			table.insert(out, { name = fmt.truncate(tostring(choice), 100), value = choice })
		end
	end
	return self:_callback(CB.AutocompleteResult, { choices = json.array(out) })
end

-- shorthand for an ephemeral error reply ("❌ message")
function Context:error(text: string): (any, any)
	local message = { content = "❌ " .. text, ephemeral = true, allowedMentions = false }
	if self.kind == "autocomplete" then
		return self:respond({})
	end
	if self.isInteraction and self.responded and self.deferred and not self.replied then
		-- a deferred response keeps its visibility, so send the error separately when it was public
		if self.ephemeral then
			return self:reply(message)
		end
		self.api.interactions.deleteOriginal(self.token)
		self.replied = true
		return self.api.interactions.followUp(self.token, message, true)
	end
	return self:reply(message)
end
Context.fail = Context.error

-- messages, reactions, DMs -------------------------------------------------------------------

-- reacts to the command message (prefix), the component's message, or a message message
-- commands target; pass `messageId` to pick another message in this channel
function Context:react(emoji: any, messageId: string?): (any, any)
	local message = targetMessage(self)
	local id = messageId or (message and message.id)
	local channelId = (message and message.channel_id) or self.channelId
	if id == nil or channelId == nil then
		return nil, "no message to react to"
	end
	return self.api.channels.react(channelId, id, emoji)
end

function Context:typing(): (any, any)
	if self.channelId == nil then
		return nil, "no channel"
	end
	return self.api.channels.typing(self.channelId)
end

-- DMs the user who ran the command (or `userId`)
function Context:dm(input: any, userId: string?): (any, any)
	local id = userId or (self.user and self.user.id)
	if id == nil then
		return nil, "no user to DM"
	end
	return self.api.users.dm(id, input)
end

-- waiting for things -------------------------------------------------------------------------

local function idSet(value: any): { [string]: boolean }?
	if value == nil then
		return nil
	end
	local set = {}
	for _, v in (if type(value) == "table" then value else { value }) do
		set[v] = true
	end
	return set
end

-- the matcher shared by awaitComponent and collect
function Context:_componentMatcher(options: { [string]: any }): (any) -> boolean
	local customIds = idSet(options.customId or options.customIds)
	local messageId = options.message
	if type(messageId) == "table" then
		messageId = messageId.id
	end
	if messageId == nil and customIds == nil and self.replyMessage then
		messageId = self.replyMessage.id
	end
	local users = nil
	if options.user == false or options.anyone then
		users = nil
	elseif options.users then
		users = idSet(options.users)
	elseif options.user then
		users = idSet(options.user)
	elseif self.user then
		users = idSet(self.user.id)
	end
	local filter = options.filter
	return function(c: any): boolean
		if customIds and not customIds[c.customId] then
			return false
		end
		if messageId and not (c.message and c.message.id == messageId) then
			return false
		end
		if customIds == nil and messageId == nil and c.channelId ~= self.channelId then
			return false
		end
		if users and not (c.user and users[c.user.id]) then
			return false
		end
		if filter and not filter(c) then
			return false
		end
		return true
	end
end

--[[
	Waits for one component interaction and returns its context, or nil on timeout.
	options: { customId = id | { ids }, message = id | message, user = id | false (anyone),
	           users = { ids }, timeout = seconds (default 60), filter = fn(ctx) -> bool }
	Without customId or message it matches components on this context's reply.
]]
function Context:awaitComponent(options: { [string]: any }?): any
	local optionsTF = options or {}
	local ch = task.channel()
	local handle = self.bot:_addCollector("component", self:_componentMatcher(options), function(c)
		ch:trySend(c)
	end)
	local got, value = ch:recv(optionsTF.timeout or 60)
	handle:stop()
	return if got then value else nil
end

--[[
	Calls `handler(componentCtx)` for every matching component until `timeout` seconds pass
	without one (idle, default 120), `max` are collected, or `collector:stop()` is called.
	Doesn't wait; `options.onEnd(reason)` runs at the end ("timeout", "max", "stopped").
]]
function Context:collect(options: { [string]: any }, handler: (any) -> ()): any
	local count = 0
	local idle = options.timeout or 120
	local timer = nil
	local handle
	local function finish(reason: string)
		if handle.stopped then
			return
		end
		handle:stop()
		if timer then
			pcall(task.cancel, timer)
		end
		if options.onEnd then
			task.spawn(options.onEnd, reason)
		end
	end
	local function arm()
		if timer then
			pcall(task.cancel, timer)
		end
		timer = task.delay(idle, finish, "timeout")
	end
	handle = self.bot:_addCollector("component", self:_componentMatcher(options), function(c)
		count += 1
		arm()
		task.spawn(handler, c)
		if options.max and count >= options.max then
			finish("max")
		end
	end)
	arm()
	return {
		stop = function()
			finish("stopped")
		end,
		count = function()
			return count
		end,
	}
end

--[[
	Waits for a message in this channel from this user (needs message intents). Returns the
	message, or nil on timeout.
	options: { timeout = 60, channelId, user = id | false, filter = fn(message) -> bool }
]]
function Context:awaitMessage(options: { [string]: any }?): any
	local optionsTF = options or {}
	local channelId = optionsTF.channelId or self.channelId
	local userId = if optionsTF.user == false then nil else (optionsTF.user or (self.user and self.user.id))
	return self.bot:waitFor("MESSAGE_CREATE", function(m)
		if channelId and m.channel_id ~= channelId then
			return false
		end
		if userId and not (m.author and m.author.id == userId) then
			return false
		end
		return optionsTF.filter == nil or optionsTF.filter(m)
	end, optionsTF.timeout or 60)
end

-- waits for any gateway event: ctx:waitFor("MESSAGE_REACTION_ADD", function(d) ... end, 30)
function Context:waitFor(event: string, filter: ((any) -> boolean)?, timeout: number?): any
	return self.bot:waitFor(event, filter, timeout)
end

--[[
	Asks a yes/no question with buttons. Returns true, false, or nil (timed out). The buttons
	are disabled afterwards.
	options: { yes = "Confirm", no = "Cancel", timeout = 60, ephemeral, user = id | false }
]]
function Context:confirm(question: any, options: { [string]: any }?): boolean?
	local optionsTF = options or {}
	local nonce = crypto.randomBytes(6, "hex")
	local yesId, noId = `~confirm:{nonce}:yes`, `~confirm:{nonce}:no`
	local row = ui.row(
		ui.button({ label = optionsTF.yes or "Confirm", style = "success", customId = yesId }),
		ui.button({ label = optionsTF.no or "Cancel", style = "danger", customId = noId })
	)
	local message = if type(question) == "string" then { content = question } else table.clone(question)
	message.components = table.clone(message.components or {})
	table.insert(message.components, row)
	if optionsTF.ephemeral ~= nil then
		message.ephemeral = optionsTF.ephemeral
	end
	local sent, err = self:reply(message)
	if sent == nil then
		self:log("confirm: couldn't send:", tostring(err))
		return nil
	end
	local clicked = self:awaitComponent({ customId = { yesId, noId }, user = optionsTF.user, timeout = optionsTF.timeout or 60 })
	local disabled = ui.disableAll(message.components)
	if clicked then
		clicked:update({ components = disabled })
		return clicked.customId == yesId
	end
	if self.isInteraction then
		self:edit({ components = disabled })
	elseif type(sent) == "table" and sent.id then
		self.api.channels.editMessage(sent.channel_id, sent.id, { components = disabled })
	end
	return nil
end

--[[
	Shows `pages` (anything ctx:reply accepts) with previous/next buttons for whoever ran the
	command. Returns once the menu times out (default: 120 seconds idle).
	options: { timeout, start = 1, ephemeral, user = id | false, wrap = true }
]]
function Context:paginate(pages: { any }, options: { [string]: any }?)
	local optionsTF = options or {}
	if #pages == 0 then
		return
	end
	local nonce = crypto.randomBytes(6, "hex")
	local prevId, nextId, pageId = `~page:{nonce}:prev`, `~page:{nonce}:next`, `~page:{nonce}:n`
	local index = math.clamp(optionsTF.start or 1, 1, #pages)

	local function render(disabled: boolean?): any
		local page = pages[index]
		local message
		if type(page) == "string" then
			message = { content = page }
		elseif type(page) == "table" and type(page.type) == "number" then
			message = { components = { page } }
		elseif type(page) == "table" and page.description ~= nil and page.components == nil and page.content == nil then
			message = { embeds = { page } }
		else
			message = table.clone(page)
		end
		message.components = table.clone(message.components or {})
		if #pages > 1 then
			local row = ui.row(
				ui.button({ emoji = "◀️", style = "secondary", customId = prevId, disabled = disabled or (not optionsTF.wrap and index == 1) }),
				ui.button({ label = `{index} / {#pages}`, style = "secondary", customId = pageId, disabled = true }),
				ui.button({ emoji = "▶️", style = "secondary", customId = nextId, disabled = disabled or (not optionsTF.wrap and index == #pages) })
			)
			table.insert(message.components, if disabled then ui.disableAll({ row })[1] else row)
		end
		if optionsTF.ephemeral ~= nil then
			message.ephemeral = optionsTF.ephemeral
		end
		return message
	end
	if optionsTF.wrap == nil then
		optionsTF.wrap = true
	end

	local sent = self:reply(render())
	if sent == nil or #pages < 2 then
		return
	end
	local done = task.event()
	self:collect({ customId = { prevId, nextId }, user = optionsTF.user, timeout = optionsTF.timeout or 120, onEnd = function()
		done:set()
	end }, function(c)
		if c.customId == prevId then
			index = if index == 1 then #pages else index - 1
		else
			index = if index == #pages then 1 else index + 1
		end
		local m = render()
		m.ephemeral = nil
		c:update(m)
	end)
	done:wait()
	local final = render(true)
	final.ephemeral = nil
	if self.isInteraction then
		self:edit(final)
	elseif type(sent) == "table" and sent.id then
		self.api.channels.editMessage(sent.channel_id, sent.id, final)
	end
end

-- permissions --------------------------------------------------------------------------------

-- the permissions of whoever ran the command, in this channel
function Context:memberPermissions(): number
	if self.member and self.member.permissions then
		return tonumber(self.member.permissions) or 0
	end
	if not self.inGuild then
		return Permissions.All
	end
	local guild = self:fetchGuild()
	local channel = self.channelId and self:fetchChannel()
	if channel and channel.parent_id and (channel.type == 10 or channel.type == 11 or channel.type == 12) then
		-- threads use their parent's overwrites
		channel = self.bot:fetchChannel(channel.parent_id) or channel
	end
	local member = self.member or self:fetchMember()
	return Permissions.compute(guild, member, self.user and self.user.id, channel)
end

-- the bot's permissions in this channel
function Context:botPermissions(): number
	if self.appPermissions then
		return tonumber(self.appPermissions) or 0
	end
	if not self.inGuild then
		return Permissions.All
	end
	local botId = self.bot.user and self.bot.user.id
	if botId == nil then
		return 0
	end
	local guild = self:fetchGuild()
	local channel = self.channelId and self:fetchChannel()
	if channel and channel.parent_id and (channel.type == 10 or channel.type == 11 or channel.type == 12) then
		channel = self.bot:fetchChannel(channel.parent_id) or channel
	end
	local member = self:fetchMember(botId)
	return Permissions.compute(guild, member, botId, channel)
end

-- whether the user has every permission in `perms` (names, a list, or a mask)
function Context:hasPermission(perms: any): (boolean, { string })
	local missing = Permissions.missing(self:memberPermissions(), perms)
	return #missing == 0, missing
end

function Context:botHasPermission(perms: any): (boolean, { string })
	local missing = Permissions.missing(self:botPermissions(), perms)
	return #missing == 0, missing
end

function Context:isOwner(userId: string?): boolean
	local id = userId or (self.user and self.user.id)
	return id ~= nil and self.bot:isOwner(id)
end

-- lookups ------------------------------------------------------------------------------------

function Context:fetchGuild(): any
	if self.guildId == nil then
		return nil
	end
	return self.bot:fetchGuild(self.guildId)
end

function Context:fetchChannel(channelId: string?): any
	local id = channelId or self.channelId
	if id == nil then
		return nil
	end
	return self.bot:fetchChannel(id)
end

-- a guild member (with .user), the caller by default
function Context:fetchMember(userId: string?): any
	if self.guildId == nil then
		return nil
	end
	local id = userId or (self.user and self.user.id)
	if id == nil then
		return nil
	end
	if self.member and self.user and id == self.user.id and self.member.roles then
		local m = table.clone(self.member)
		m.user = m.user or self.user
		return m
	end
	return self.bot:fetchMember(self.guildId, id)
end

function Context:fetchUser(userId: string): any
	for _, user in (self.message and self.message.mentions) or {} do
		if user.id == userId then
			return user
		end
	end
	return self.bot:fetchUser(userId)
end

-- a role by id or (case-insensitive) name in this guild
function Context:fetchRole(idOrName: string): any
	if self.guildId == nil then
		return nil
	end
	local guild = self:fetchGuild()
	local roles = guild and guild.roles
	if roles == nil then
		roles = self.api.guilds.roles(self.guildId)
	end
	local lower = string.lower(idOrName)
	for _, role in roles or {} do
		if role.id == idOrName or string.lower(role.name) == lower then
			return role
		end
	end
	return nil
end

-- what commands.parseArgs uses to turn mentions into objects
function Context:_lookup(): any
	return {
		user = function(id)
			local user = self:fetchUser(id)
			return user
		end,
		member = function(id)
			return self:fetchMember(id)
		end,
		channel = function(id)
			local channel = self:fetchChannel(id)
			if channel and self.guildId and channel.guild_id and channel.guild_id ~= self.guildId then
				return nil
			end
			return channel
		end,
		role = function(id)
			return self:fetchRole(id)
		end,
	}
end

-- small conveniences -------------------------------------------------------------------------

-- an option/argument value, or `default`
function Context:getOption(name: string, default: any?): any
	local value = self.options and self.options[name]
	if value == nil then
		return default
	end
	return value
end

-- a modal field value
function Context:field(customId: string, default: any?): any
	local value = self.fields and self.fields[customId]
	if value == nil then
		return default
	end
	return value
end

-- the caller as a mention
function Context:mention(): string
	return if self.user then fmt.user(self.user.id) else ""
end

-- "nickname > global name > username" for the caller (or another user + member)
function Context:displayName(user: any?, member: any?): string
	local u = user or self.user
	if u == nil then
		return "unknown"
	end
	return fmt.displayName(u, member or (if user == nil then self.member else u.member))
end

-- gateway heartbeat latency in seconds (nil before the first heartbeat ACK)
function Context:latency(): number?
	return self.bot.gateway and self.bot.gateway.latency
end

function Context:sleep(seconds: number?): number
	return task.wait(seconds)
end

function Context:spawn(fn: (...any) -> ...any, ...: any): thread
	return task.spawn(fn, ...)
end

function Context:log(...: any)
	local where = self.commandPath or self.customId or self.event or self.kind
	print(`[{where}]`, ...)
end

-- checks if the id belongs to a slash command and returns its clickable mention
function Context:commandMention(name: string): string
	local id = self.bot.commandIds[string.lower((string.match(name, "^%S+") or name))]
	return if id then fmt.command(name, id) else "/" .. name
end

-- whether this component/modal/command came from `customId` / name
function Context:is(name: string): boolean
	return self.name == name or self.customId == name or self.commandName == name
end

-- a component's selected values resolved to objects for user/role/channel/mentionable selects
function Context:selected(): { any }
	local out = {}
	local resolved = self.resolved or {}
	for _, id in self.values or {} do
		local value = (resolved.users and resolved.users[id])
			or (resolved.roles and resolved.roles[id])
			or (resolved.channels and resolved.channels[id])
			or (resolved.attachments and resolved.attachments[id])
			or id
		if type(value) == "table" and resolved.members and resolved.members[id] then
			value = table.clone(value)
			value.member = resolved.members[id]
		end
		table.insert(out, value)
	end
	return out
end

-- attachments uploaded through a modal FileUpload (by custom id)
function Context:uploads(customId: string): { any }
	local ids = self.fields and self.fields[customId] or {}
	local out = {}
	local attachments = self.resolved and self.resolved.attachments or {}
	for _, id in ids do
		table.insert(out, attachments[id] or { id = id })
	end
	return out
end

-- any component (by custom id) in the message a component is on
function Context:findComponent(customId: string): any
	return self.message and ui.find(self.message.components or {}, customId)
end

return Context
