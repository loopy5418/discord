--[[
	Bot: commands, components, modals, events and the rest, on top of the gateway client

	    local discord = require("@discord")
	    local bot = discord.new({ token = TOKEN, prefix = "!" })

	    bot:command({
	        name = "ping", description = "Pong!", prefix = true,
	        run = function(ctx) ctx:reply("Pong!") end,
	    })
	    bot:load("commands", "events") -- or load them from files
	    bot:run()

	See README.md for a tour and types.luau for every option and context field.
]]

local task = require("@sonata/task")
local json = require("@sonata/json")
local fs = require("@sonata/fs")
local path = require("@sonata/path")
local crypto = require("@sonata/crypto")
local process = require("@sonata/process")

local gateway = require("./gateway/gateway")
local Intent = require("./gateway/intents")

local Rest = require("./rest")
local makeApi = require("./api")
local Cache = require("./cache")
local Context = require("./context")
local commands = require("./commands")
local ui = require("./components")
local fmt = require("./format")
local enums = require("./enums")
local Permissions = require("./permissions")
local messages = require("./messages")
local loader = require("./loader")
local types = require("./types")

export type Context = types.Context
export type CommandDefinition = types.CommandDefinition
export type ComponentDefinition = types.ComponentDefinition
export type ModalDefinition = types.ModalDefinition
export type EventDefinition = types.EventDefinition
export type BotOptions = types.BotOptions

local Bot = {}
Bot.__index = Bot

local function log(...)
	print("[bot]", ...)
end

-- "messageCreate" / "message_create" / "MESSAGE_CREATE" -> "MESSAGE_CREATE"
local function eventName(name: string): string
	if name == "*" then
		return name
	end
	local snake = string.gsub(name, "(%l)(%u)", "%1_%2")
	return string.upper(snake)
end
Bot.eventName = eventName

function Bot.new(options: BotOptions?): any
	local optionsTF = options or {}
	local token = optionsTF.token or process.env.DISCORD_TOKEN
	if token == nil or token == "" then
		error("Bot.new: pass a token (or set DISCORD_TOKEN env variable)", 2)
	end
	token = string.gsub(string.gsub(token, "%s+$", ""), "^Bot%s+", "")

	local o: { [string]: any } = table.clone(optionsTF)
	o.token = nil
	if o.mentionPrefix == nil then
		o.mentionPrefix = true
	end
	if o.caseInsensitive == nil then
		o.caseInsensitive = true
	end
	if o.ignoreBots == nil then
		o.ignoreBots = true
	end
	if o.syncCommands == nil then
		o.syncCommands = true
	end
	if o.autoDefer == nil then
		o.autoDefer = true
	end
	if o.allowedMentions == nil then
		o.allowedMentions = { parse = { "users" }, repliedUser = false }
	end
	if o.errorMessage == nil then
		o.errorMessage = "Something went wrong while running this."
	end
	if o.commandCache == nil then
		o.commandCache = path.join(sonata.project.root, ".commands.lock.json")
	end

	local intents = o.intents
	if intents == nil then
		intents = { "Guilds", "GuildMessages", "DirectMessages" }
		if o.prefix then
			table.insert(intents, "MessageContent")
		end
	end

	local self = setmetatable({}, Bot)
	self.options = o
	self.rest = Rest.new(token, { debug = o.debugRest })
	self.api = makeApi(self.rest, self)
	self.cache = Cache.new()
	self.cache.enabled = o.cache ~= false
	self.gateway = gateway.new({ token = token, intents = intents, presence = o.presence, debug = o.debug })
	self.intents = self.gateway.intents

	self.applicationId = o.applicationId
	self.user = nil
	self.owners = {} :: { [string]: boolean }
	for _, id in o.owners or {} do
		self.owners[id] = true
	end
	self.store = {} -- shared state for your commands: ctx.store
	self.ready = task.event() -- set after the first READY
	self.startedAt = os.time()

	self.commandList = {} -- normalized definitions in registration order
	self.commands = {} -- "slash:name" / "user:name" / "message:name" -> definition
	self.prefixCommands = {} -- lowercase name/alias -> definition
	self.commandIds = {} -- slash command name -> id (after sync)
	self.components = {} -- custom id name -> definition
	self.componentPatterns = {} -- definitions with `match`
	self.modals = {}
	self.modalPatterns = {}

	self._events = {} -- EVENT -> { { run, once } }
	self._waiters = {} -- EVENT -> { { filter, ch } }
	self._collectors = { component = {}, modal = {} }
	self._middleware = {}
	self._cooldowns = {} -- key -> expiry
	self._errorHandlers = {}
	self._readyOnce = false

	self.gateway:on("*", function(event, d)
		self:_dispatch(event, d)
	end)
	return self
end

--[[
	Definition helpers. Called on the module they tag a table so a file can say what it holds:

	    return Bot.command({ name = "ping", ... })

	Called on a bot they register it right away: bot:command({ ... }).
]]

local function helper(kind: string, register: string, fixType: string?)
	return function(a: any, b: any?): any
		if getmetatable(a) == Bot then
			local def = b
			if fixType and def.type == nil then
				def.type = fixType
			end
			return a[register](a, def)
		end
		local def = a
		def.__kind = kind
		if fixType and def.type == nil then
			def.type = fixType
		end
		return def
	end
end

Bot.command = helper("command", "addCommand")
Bot.slash = helper("command", "addCommand")
Bot.prefix = helper("command", "addCommand", "prefix")
Bot.userCommand = helper("command", "addCommand", "user")
Bot.messageCommand = helper("command", "addCommand", "message")
Bot.component = helper("component", "addComponent")
Bot.modal = helper("modal", "addModal")
Bot.event = helper("event", "addEvent")

-- libraries, also on every context
Bot.ui = ui
Bot.fmt = fmt
Bot.enums = enums
Bot.permissions = Permissions
Bot.intents = Intent
Bot.messages = messages
-- REST without a bot: discord.makeApi(discord.Rest.new(token)).users.me()
Bot.Rest = Rest
Bot.makeApi = makeApi

-- registration -------------------------------------------------------------------------------

local function commandKey(def: any): string
	local kind = if def.kind == "user" or def.kind == "message" then def.kind else "slash"
	return kind .. ":" .. string.lower(def.name)
end

-- registers a command (slash, prefix, hybrid, user or message)
function Bot:addCommand(def: CommandDefinition, source: string?): any
	local c = commands.normalize(def, self.options)
	c.source = source
	if c.kind ~= "prefix" and (c.slash or c.kind ~= "slash") then
		local key = commandKey(c)
		if self.commands[key] then
			error(`command "{c.name}" is defined twice ({self.commands[key].source or "?"} and {source or "?"})`, 2)
		end
		self.commands[key] = c
	end
	if c.isPrefix then
		for _, name in { c.name, table.unpack(c.aliases) } do
			local key = if self.options.caseInsensitive then string.lower(name) else name
			if self.prefixCommands[key] then
				error(`prefix command "{name}" is defined twice`, 2)
			end
			self.prefixCommands[key] = c
		end
		if self.options.prefix == nil and not self._warnedPrefix then
			self._warnedPrefix = true
			log(`note: "{c.name}" is a prefix command but no prefix is set; only @mentions will trigger it`)
		end
	end
	table.insert(self.commandList, c)
	return c
end

-- registers a component handler: { customId = "name" | { names }, match = "lua pattern", run }
-- Custom ids look like "name" or "name:param1:param2"; the name picks the handler and the
-- params go to run(ctx, param1, param2) and ctx.params.
function Bot:addComponent(def: ComponentDefinition, source: string?): any
	return self:_addHandler(def, source, self.components, self.componentPatterns, "component")
end

function Bot:addModal(def: ModalDefinition, source: string?): any
	return self:_addHandler(def, source, self.modals, self.modalPatterns, "modal")
end

function Bot:_addHandler(def: any, source: string?, map: any, patterns: any, what: string): any
	if type(def.run) ~= "function" then
		error(`{what} handler needs a run function`, 3)
	end
	local d = table.clone(def)
	d.source = source
	if type(d.cooldown) == "number" then
		d.cooldown = { seconds = d.cooldown, scope = "user" }
	end
	if d.match then
		table.insert(patterns, d)
	end
	local ids = d.customId or d.name
	if ids then
		for _, id in (if type(ids) == "table" then ids else { ids }) do
			if map[id] then
				error(`{what} "{id}" is defined twice`, 3)
			end
			map[id] = d
		end
	elseif d.match == nil then
		error(`{what} handler needs a customId or a match pattern`, 3)
	end
	return d
end

-- registers an event handler; `run(ctx, data)`
function Bot:on(event: string, run: (Context, any) -> ()): any
	local name = eventName(event)
	local list = self._events[name]
	if list == nil then
		list = {}
		self._events[name] = list
	end
	local entry = { run = run, once = false }
	table.insert(list, entry)

	local receives, needed = Intent.receives(self.intents, name)
	if not receives and needed then
		log(`warning: "{name}" needs one of these intents, which the bot doesn't have: {table.concat(needed, ", ")}`)
	end
	return self
end

function Bot:once(event: string, run: (Context, any) -> ()): any
	self:on(event, run)
	local list = self._events[eventName(event)]
	list[#list].once = true
	return self
end

function Bot:off(event: string, run: any?)
	local list = self._events[eventName(event)]
	if list == nil then
		return
	end
	for i = #list, 1, -1 do
		if run == nil or list[i].run == run then
			table.remove(list, i)
		end
	end
end

function Bot:addEvent(def: EventDefinition, source: string?)
	if type(def.event) ~= "string" or type(def.run) ~= "function" then
		error(`event definitions need an event name and a run function ({source or "?"})`, 2)
	end
	if def.once then
		self:once(def.event, def.run)
	else
		self:on(def.event, def.run)
	end
end

--[[
	Middleware runs around every command, component and modal handler:

	    bot:use(function(ctx, next)
	        local started = os.clock()
	        next()
	        ctx:log("took", os.clock() - started)
	    end)

	Not calling next() stops the handler from running.
]]
function Bot:use(middleware: (Context, () -> ()) -> ())
	table.insert(self._middleware, middleware)
	return self
end

-- called with (err, ctx) when a handler errors; the default prints the traceback
function Bot:onError(handler: (string, Context?) -> ())
	table.insert(self._errorHandlers, handler)
	return self
end

--[[
	Registers anything a module can hold:
	- a definition tagged by Bot.command/component/modal/event (or with `kind = "command"` etc.)
	- an untagged table: `event` -> event, `customId`/`match` -> component (`modal = true` for
	  modals), `name` + `run` -> command
	- a list of any of these
	- a table with `commands`, `components`, `modals` and/or `events` lists
	- a function: a plugin, called as fn(bot)
]]
function Bot:add(value: any, source: string?)
	if type(value) == "function" then
		value(self)
		return
	end
	if type(value) ~= "table" then
		error(`can't register a {typeof(value)} ({source or "?"}): modules should return a definition, a list or a function`, 2)
	end
	local kind = value.__kind or value.kind
	if kind == "command" then
		self:addCommand(value, source)
	elseif kind == "component" then
		self:addComponent(value, source)
	elseif kind == "modal" then
		self:addModal(value, source)
	elseif kind == "event" then
		self:addEvent(value, source)
	elseif value.event and value.run then
		self:addEvent(value, source)
	elseif (value.customId or value.match) and value.run then
		if value.modal then
			self:addModal(value, source)
		else
			self:addComponent(value, source)
		end
	elseif value.name and (value.run or value.subcommands) then
		self:addCommand(value, source)
	elseif value.commands or value.components or value.modals or value.events then
		for _, c in value.commands or {} do
			self:addCommand(c, source)
		end
		for _, c in value.components or {} do
			self:addComponent(c, source)
		end
		for _, m in value.modals or {} do
			self:addModal(m, source)
		end
		for _, e in value.events or {} do
			self:addEvent(e, source)
		end
	elseif #value > 0 then
		for _, item in value do
			self:add(item, source)
		end
	else
		error(`don't know how to register the table from {source or "?"}: give it a name and run (command), customId (component), event (event), or tag it with Bot.command(...)`, 2)
	end
end

--[[
	Loads parts of the bot from files and folders (see bot/loader.luau). Relative paths are
	resolved from the calling file. Each module's return value goes through `Bot:add`.
	Returns how many modules were loaded.
]]
function Bot:load(...: any): number
	local baseDir = loader.callerDir(2)
	local count = 0
	for _, target in { ... } do
		if type(target) == "table" or type(target) == "function" then
			self:add(target, "<table>")
			count += 1
		else
			for _, entry in loader.collect(target, baseDir, self.options.assets) do
				local ok, err = pcall(self.add, self, entry.module, entry.file)
				if not ok then
					error(`{entry.file}: {err}`, 0)
				end
				count += 1
			end
		end
	end
	if self.options.debug then
		log(`loaded {count} module(s)`)
	end
	return count
end

-- lookups (cache first) ----------------------------------------------------------------------

function Bot:fetchUser(userId: string): any
	local user = self.cache:user(userId)
	if user then
		return user
	end
	user = self.api.users.get(userId)
	if user then
		self.cache:putUser(user)
	end
	return user
end

function Bot:fetchGuild(guildId: string): any
	local guild = self.cache:guild(guildId)
	if guild then
		return guild
	end
	guild = self.api.guilds.get(guildId)
	if guild and self.cache.enabled then
		self.cache.guilds[guildId] = guild
	end
	return guild
end

function Bot:fetchChannel(channelId: string): any
	local channel = self.cache:channel(channelId)
	if channel then
		return channel
	end
	channel = self.api.channels.get(channelId)
	if channel and self.cache.enabled then
		self.cache:putChannel(channel)
	end
	return channel
end

-- a member with .user attached
function Bot:fetchMember(guildId: string, userId: string): any
	local member = self.cache:member(guildId, userId)
	if member then
		local m = table.clone(member)
		m.user = self.cache:user(userId) or { id = userId }
		return m
	end
	member = self.api.guilds.member(guildId, userId)
	if member then
		self.cache:putMember(guildId, member)
	end
	return member
end

function Bot:isOwner(userId: string): boolean
	return self.owners[userId] == true
end

-- presence -----------------------------------------------------------------------------------

function Bot:setPresence(presence: { [string]: any })
	return self.gateway:setPresence(presence)
end

-- bot:setStatus("idle", "with fire", "playing"); type defaults to "custom" (just the text)
function Bot:setStatus(status: string?, activity: string?, activityType: (string | number)?)
	local activities = {}
	if activity then
		local t = enums.resolve(enums.ActivityType, activityType or "custom", "activity type")
		local a: { [string]: any } = { name = activity, type = t }
		if t == enums.ActivityType.Custom then
			a.state = activity
			a.name = "Custom Status"
		end
		table.insert(activities, a)
	end
	return self.gateway:setPresence({ status = status or "online", activities = activities })
end

-- waiting ------------------------------------------------------------------------------------

--[[
	Waits for a gateway event whose data passes `filter`, and returns that data (nil on
	timeout, default 60 seconds).

	    local reaction = bot:waitFor("MESSAGE_REACTION_ADD", function(d) return d.message_id == id end, 30)
]]
function Bot:waitFor(event: string, filter: ((any) -> boolean)?, timeout: number?): any
	local name = eventName(event)
	local list = self._waiters[name]
	if list == nil then
		list = {}
		self._waiters[name] = list
	end
	local ch = task.channel()
	local waiter = { filter = filter, ch = ch }
	table.insert(list, waiter)
	local got, value = ch:recv(timeout or 60)
	local index = table.find(list, waiter)
	if index then
		table.remove(list, index)
	end
	return if got then value else nil
end

-- component/modal collectors used by ctx:awaitComponent, ctx:collect and ctx:prompt
function Bot:_addCollector(kind: string, match: (any) -> boolean, onCollect: (any) -> ()): any
	local list = self._collectors[kind]
	local handle = { stopped = false }
	local entry = { match = match, onCollect = onCollect, handle = handle }
	function handle.stop()
		if handle.stopped then
			return
		end
		handle.stopped = true
		local index = table.find(list, entry)
		if index then
			table.remove(list, index)
		end
	end
	table.insert(list, entry)
	return handle
end

function Bot:_collect(kind: string, ctx: any): boolean
	for _, entry in table.clone(self._collectors[kind]) do
		if not entry.handle.stopped then
			local ok, matched = pcall(entry.match, ctx)
			if ok and matched then
				entry.onCollect(ctx)
				return true
			end
		end
	end
	return false
end

-- dispatching --------------------------------------------------------------------------------

function Bot:_handleError(err: any, ctx: any?)
	local text = tostring(err)
	if #self._errorHandlers == 0 then
		local where = if ctx then (ctx.commandPath or ctx.customId or ctx.event or ctx.kind) else "?"
		print(`[bot] error in {where}:\n{text}`)
	end
	for _, handler in self._errorHandlers do
		local ok, e = pcall(handler, text, ctx)
		if not ok then
			print("[bot] error handler failed:", e)
		end
	end
	if ctx and self.options.errorMessage and ctx.kind ~= "event" and ctx.kind ~= "autocomplete" then
		if not ctx.replied then
			pcall(ctx.error, ctx, self.options.errorMessage)
		end
	end
end

-- runs fn through the middleware chain, catching errors
function Bot:_invoke(ctx: any, fn: () -> ())
	local i = 0
	local function nextStep()
		i += 1
		local mw = self._middleware[i]
		if mw then
			return mw(ctx, nextStep)
		end
		return fn()
	end
	local ok, err = xpcall(nextStep, debug.traceback)
	if not ok then
		self:_handleError(err, ctx)
	end
end

-- cooldown key and remaining seconds; scope: "user" | "guild" | "channel" | "global"
function Bot:_cooldown(ctx: any, name: string, cooldown: any): (string?, number?)
	if cooldown == nil then
		return nil, nil
	end
	local scope = cooldown.scope or "user"
	local id = if scope == "guild" then (ctx.guildId or (ctx.user and ctx.user.id))
		elseif scope == "channel" then ctx.channelId
		elseif scope == "global" then "global"
		else (ctx.user and ctx.user.id)
	local key = `{name}|{scope}|{id}`
	local expires = self._cooldowns[key]
	local now = os.time()
	if expires and expires > now then
		return key, expires - now
	end
	return key, nil
end

--[[
	Runs the checks shared by commands, components and modals. Returns nil, or the message to
	show the user.
]]
function Bot:_check(ctx: any, def: any, leaf: any?): string?
	local function field(name: string): any
		if leaf and leaf[name] ~= nil then
			return leaf[name]
		end
		return def[name]
	end

	if field("ownerOnly") and not ctx:isOwner() then
		return "Only the bot's owners can use this."
	end
	if (field("guildOnly") or (ctx.isPrefix and def.contexts and #def.contexts == 1 and def.contexts[1] == "guild")) and not ctx.inGuild then
		return "This only works in servers."
	end
	if field("dmOnly") and ctx.inGuild then
		return "This only works in DMs."
	end
	if ctx.isPrefix and def.nsfw and ctx.inGuild then
		local channel = ctx:fetchChannel()
		if not (channel and channel.nsfw) then
			return "This only works in age-restricted channels."
		end
	end
	-- Discord enforces `permissions` for application commands; check it ourselves elsewhere
	local perms = field("permissions")
	local enforced = ctx.isInteraction and (ctx.kind == "slash" or ctx.kind == "user" or ctx.kind == "message")
	if perms and ctx.inGuild and not enforced then
		local ok, missing = ctx:hasPermission(perms)
		if not ok then
			local labels = {}
			for _, name in missing do
				table.insert(labels, Permissions.label(name))
			end
			return `You need these permissions: {table.concat(labels, ", ")}`
		end
	end
	local botPerms = field("botPermissions")
	if botPerms and ctx.inGuild and ctx.botPresent then
		local ok, missing = ctx:botHasPermission(botPerms)
		if not ok then
			local labels = {}
			for _, name in missing do
				table.insert(labels, Permissions.label(name))
			end
			return `I need these permissions: {table.concat(labels, ", ")}`
		end
	end
	for _, check in field("checks") or {} do
		local ok, message = check(ctx)
		if ok == false or type(ok) == "string" then
			return if type(ok) == "string" then ok else (message or "You can't use this.")
		end
	end
	local cooldown = field("cooldown")
	if cooldown and not ctx:isOwner() then
		local key, remaining = self:_cooldown(ctx, ctx.commandPath or ctx.name or def.name or "?", cooldown)
		if remaining then
			return cooldown.message or `Slow down! Try again {fmt.timestamp(os.time() + remaining, "R")}.`
		end
		if key then
			self._cooldowns[key] = os.time() + cooldown.seconds
		end
	end
	return nil
end

function Bot:_runCommand(ctx: any, def: any, leaf: any, arg: any)
	ctx.command = def
	ctx.subcommandDef = if leaf ~= def then leaf else nil
	ctx.commandName = def.name
	ctx.commandPath = ctx.commandPath or def.name
	local ephemeral = leaf.ephemeral
	if ephemeral == nil then
		ephemeral = def.ephemeral
	end
	ctx.ephemeralDefault = ephemeral == true

	local denied = self:_check(ctx, def, leaf)
	if denied then
		ctx:error(denied)
		return
	end

	local defer = leaf.defer
	if defer == nil then
		defer = def.defer
	end
	if defer then
		ctx:defer({ ephemeral = if defer == "ephemeral" then true else ctx.ephemeralDefault })
	elseif ctx.isInteraction and self.options.autoDefer then
		task.delay(2.3, function()
			if not ctx.responded then
				ctx:defer()
			end
		end)
	end

	local run = leaf.run or def.run
	self:_invoke(ctx, function()
		run(ctx, arg)
	end)
end

-- the component/modal handler for a context, from collectors, inline callbacks, then registry
function Bot:_routeComponent(ctx: any, map: any, patterns: any, kind: string)
	if self:_collect(kind, ctx) then
		return
	end
	local inline = ui.findCallback(ctx.customId)
	if inline then
		ctx.commandPath = "inline " .. kind
		self:_invoke(ctx, function()
			inline(ctx, if kind == "modal" then ctx.fields else ctx.values)
		end)
		return
	end
	local def = map[ctx.name] or map[ctx.customId]
	if def == nil then
		for _, p in patterns do
			local captures = { string.match(ctx.customId, p.match) }
			if #captures > 0 then
				def = p
				if not (#captures == 1 and captures[1] == ctx.customId) then
					ctx.params = captures
				end
				break
			end
		end
	end
	if def == nil then
		if string.sub(ctx.customId, 1, 1) == "~" then
			-- an inline handler that expired, or a confirm/paginate that timed out
			ctx:error("This has expired.")
		elseif self.options.debug then
			log(`no {kind} handler for custom id "{ctx.customId}"`)
		end
		return
	end
	ctx.commandPath = def.customId and tostring(if type(def.customId) == "table" then ctx.name else def.customId) or def.match
	ctx.ephemeralDefault = def.ephemeral == true
	local denied = self:_check(ctx, def)
	if denied then
		ctx:error(denied)
		return
	end
	if def.defer == "update" or def.defer == true then
		ctx:deferUpdate()
	elseif def.defer == "reply" or def.defer == "ephemeral" then
		ctx:defer({ ephemeral = def.defer == "ephemeral" or ctx.ephemeralDefault })
	end
	self:_invoke(ctx, function()
		if kind == "modal" then
			def.run(ctx, ctx.fields)
		else
			def.run(ctx, table.unpack(ctx.params))
		end
	end)
end

local function filterChoices(list: { any }, value: any): { any }
	local query = string.lower(tostring(value or ""))
	local out = {}
	for _, item in list do
		local name = if type(item) == "table" then tostring(item.name or item.value) else tostring(item)
		if query == "" or string.find(string.lower(name), query, 1, true) then
			table.insert(out, item)
		end
	end
	return out
end

-- handles an INTERACTION_CREATE (from the gateway or the HTTP endpoint)
function Bot:_handleInteraction(interaction: any, transport: any?)
	local ctx = Context.fromInteraction(self, interaction, transport)
	local kind = ctx.kind
	local data = interaction.data or {}

	if kind == "slash" or kind == "user" or kind == "message" or kind == "autocomplete" then
		local key = (if kind == "autocomplete" then "slash" else kind) .. ":" .. string.lower(data.name or "")
		local def = self.commands[key]
		if def == nil then
			log(`unknown command "{data.name}" (it may need syncing)`)
			if kind == "autocomplete" then
				ctx:respond({})
			else
				ctx:error("This command isn't available right now.")
			end
			return
		end

		if kind == "user" or kind == "message" then
			local resolved = data.resolved or {}
			ctx.targetId = data.target_id
			if kind == "user" then
				local user = resolved.users and resolved.users[data.target_id]
				local member = resolved.members and resolved.members[data.target_id]
				if member then
					member = table.clone(member)
					member.user = user
				end
				ctx.target = user
				ctx.targetMember = member
			else
				ctx.target = resolved.messages and resolved.messages[data.target_id]
			end
			self:_runCommand(ctx, def, def, ctx.target)
			return
		end

		local leaf, commandPath, raw, group, subcommand = commands.resolveLeaf(def, data)
		if leaf == nil then
			ctx:error("Unknown subcommand.")
			return
		end
		ctx.commandPath = commandPath
		ctx.group = group
		ctx.subcommand = subcommand
		local values, focused = commands.resolveOptions(leaf.options, raw, data.resolved)
		ctx.options = values
		ctx.args = values

		if kind == "autocomplete" then
			ctx.command = def
			ctx.commandName = def.name
			ctx.focused = focused
			local handler = focused and focused.definition and focused.definition.autocomplete
			if type(handler) ~= "function" and type(handler) ~= "table" then
				handler = leaf.autocomplete or def.autocomplete
			end
			self:_invoke(ctx, function()
				local result
				if type(handler) == "table" then
					result = filterChoices(handler, focused and focused.value)
				elseif type(handler) == "function" then
					result = handler(ctx, focused and focused.value, focused and focused.name)
				end
				if not ctx.responded then
					ctx:respond(if type(result) == "table" then result else {})
				end
			end)
			return
		end

		self:_runCommand(ctx, def, leaf, values)
	elseif kind == "component" then
		self:_routeComponent(ctx, self.components, self.componentPatterns, "component")
	elseif kind == "modal" then
		self:_routeComponent(ctx, self.modals, self.modalPatterns, "modal")
	end
end

function Bot:_prefixesFor(message: any): { string }
	local list = {}
	local p = self.options.prefix
	if type(p) == "function" then
		local ok, result = pcall(p, message, self)
		if ok then
			p = result
		else
			print("[bot] prefix function failed:", result)
			p = nil
		end
	end
	if type(p) == "string" then
		table.insert(list, p)
	elseif type(p) == "table" then
		for _, item in p do
			table.insert(list, item)
		end
	end
	if self.options.mentionPrefix and self.user then
		table.insert(list, `<@{self.user.id}>`)
		table.insert(list, `<@!{self.user.id}>`)
	end
	-- longest first, so "!!" wins over "!"
	table.sort(list, function(a, b)
		return #a > #b
	end)
	return list
end

-- handles a MESSAGE_CREATE that might be a prefix command
function Bot:_handleMessage(message: any)
	if next(self.prefixCommands) == nil then
		return
	end
	local author = message.author
	if author == nil or message.webhook_id then
		return
	end
	if author.bot and self.options.ignoreBots then
		return
	end
	if self.user and author.id == self.user.id then
		return
	end
	local content = message.content or ""
	if content == "" then
		return
	end

	local usedPrefix = nil
	local lowered = string.lower(content)
	for _, p in self:_prefixesFor(message) do
		local candidate = if self.options.caseInsensitive then string.lower(p) else p
		local head = if self.options.caseInsensitive then string.sub(lowered, 1, #p) else string.sub(content, 1, #p)
		if head == candidate then
			usedPrefix = p
			break
		end
	end
	if usedPrefix == nil then
		return
	end

	local rest = string.gsub(string.sub(content, #usedPrefix + 1), "^%s+", "")
	local invoked = string.match(rest, "^(%S+)")
	if invoked == nil then
		return
	end
	local key = if self.options.caseInsensitive then string.lower(invoked) else invoked
	local def = self.prefixCommands[key]
	if def == nil then
		self:_emitEvent("UNKNOWN_COMMAND", { message = message, name = invoked, prefix = usedPrefix })
		return
	end
	local after = string.gsub(string.sub(rest, #invoked + 1), "^%s+", "")

	local ctx = Context.fromMessage(self, message)
	ctx.prefix = usedPrefix
	ctx.invokedWith = invoked
	ctx.isPrefix = true

	-- walk into subcommands: "!config set key value"
	local leaf = def
	local commandPath = def.name
	while leaf.subcommandMap do
		local subName = string.match(after, "^(%S+)")
		local sub = subName and leaf.subcommandMap[string.lower(subName)]
		if sub == nil then
			if leaf.run then
				break
			end
			local display = if string.sub(usedPrefix, 1, 2) == "<@" then "@" .. (self.user and self.user.username or "bot") .. " " else usedPrefix
			ctx:reply({ content = `Usage: \`{commands.usage(leaf, display, commandPath)}\``, allowedMentions = false })
			return
		end
		leaf = sub
		commandPath ..= " " .. sub.name
		after = string.gsub(string.sub(after, #subName + 1), "^%s+", "")
		ctx.group = if sub.isGroup then sub.name else ctx.group
		ctx.subcommand = if sub.isGroup then nil else sub.name
	end
	ctx.commandPath = commandPath
	ctx.argText = after
	local rawArgs = {}
	for _, token in commands.tokenize(after) do
		table.insert(rawArgs, token.value)
	end
	ctx.rawArgs = rawArgs

	local values, err = commands.parseArgs(leaf, after, ctx:_lookup(), message.attachments)
	if values == nil then
		local display = if string.sub(usedPrefix, 1, 2) == "<@" then "@" .. (self.user and self.user.username or "bot") .. " " else usedPrefix
		ctx:reply({ content = `❌ {err}\nUsage: \`{commands.usage(leaf, display, commandPath)}\``, allowedMentions = false })
		return
	end
	ctx.options = values
	ctx.args = values
	self:_runCommand(ctx, def, leaf, values)
end

function Bot:_emitEvent(event: string, d: any)
	self:_emitOnce(event, d)
end

function Bot:_dispatch(event: string, d: any)
	self.cache:handle(event, d)

	if event == "READY" then
		self:_onReady(d)
	end

	-- waiters first, so waitFor sees events before handlers run
	local waiters = self._waiters[event]
	if waiters and #waiters > 0 then
		for _, w in table.clone(waiters) do
			local ok, matched = true, true
			if w.filter then
				ok, matched = pcall(w.filter, d)
			end
			if ok and matched then
				local index = table.find(waiters, w)
				if index then
					table.remove(waiters, index)
				end
				w.ch:trySend(d)
			end
		end
	end

	if event == "INTERACTION_CREATE" then
		task.spawn(function()
			local ok, err = xpcall(self._handleInteraction, debug.traceback, self, d)
			if not ok then
				self:_handleError(err)
			end
		end)
	elseif event == "MESSAGE_CREATE" then
		task.spawn(function()
			local ok, err = xpcall(self._handleMessage, debug.traceback, self, d)
			if not ok then
				self:_handleError(err)
			end
		end)
	end

	self:_emitOnce(event, d)
	self:_emitOnce("*", d, event)
end

-- emits to handlers, removing `once` handlers before they run so they fire a single time
function Bot:_emitOnce(event: string, d: any, realEvent: string?)
	local list = self._events[event]
	if list == nil or #list == 0 then
		return
	end
	local run = {}
	for i = #list, 1, -1 do
		local entry = list[i]
		table.insert(run, 1, entry)
		if entry.once then
			table.remove(list, i)
		end
	end
	for _, entry in run do
		task.spawn(function()
			local ctx = Context.forEvent(self, realEvent or event, d)
			local ok, err
			if realEvent then
				ok, err = xpcall(entry.run, debug.traceback, ctx, realEvent, d)
			else
				ok, err = xpcall(entry.run, debug.traceback, ctx, d)
			end
			if not ok then
				self:_handleError(err, ctx)
			end
		end)
	end
end

function Bot:_onReady(d: any)
	self.user = d.user
	if d.application and d.application.id then
		self.applicationId = self.applicationId or d.application.id
	end
	if self._readyOnce then
		return
	end
	self._readyOnce = true
	task.spawn(function()
		self:_loadOwners()
		if self.options.syncCommands then
			local ok, err = pcall(self.syncCommands, self, { force = self.options.syncCommands == "force" })
			if not ok then
				log("command sync failed:", err)
			end
		end
		self.ready:set()
	end)
	if next(self.prefixCommands) and not Intent.has(self.intents, "MessageContent") then
		log("note: prefix commands only see message content in DMs and @mentions without the MessageContent intent")
	end
end

function Bot:_loadOwners()
	if self.options.owners then
		return
	end
	local app = self:application()
	if app == nil then
		return
	end
	if app.team and app.team.members then
		for _, m in app.team.members do
			if m.user then
				self.owners[m.user.id] = true
			end
		end
	elseif app.owner then
		self.owners[app.owner.id] = true
	end
end

-- command syncing ----------------------------------------------------------------------------

local function readCache(file: string): { [string]: string }
	local ok, data = pcall(function()
		return json.decode(fs.readFile(file))
	end)
	if ok and type(data) == "table" then
		return data
	end
	return {}
end

--[[
	Registers the application commands with Discord. With the default `syncCommands = true`
	this runs on the first READY, and only sends commands whose definitions changed since the
	last sync (hashes are kept in `commandCache`). `force` sends everything.

	With `devGuild` set, every command goes to that guild instead (updates show up instantly).
]]
function Bot:syncCommands(options: { force: boolean? }?)
	if self.applicationId == nil then
		error("syncCommands: the application id isn't known yet", 2)
	end
	local force = options and options.force
	local scopes: { [string]: { any } } = {}
	for _, def in self.commandList do
		local body = commands.toJSON(def)
		if body then
			local targets = if self.options.devGuild then { self.options.devGuild } elseif def.guilds then def.guilds else { "global" }
			for _, target in targets do
				scopes[target] = scopes[target] or {}
				table.insert(scopes[target], body)
			end
		end
	end

	local cacheFile = self.options.commandCache
	local hashes = if cacheFile then readCache(cacheFile) else {}
	local appHashes = hashes[self.applicationId] or {}

	-- scopes synced before but empty now get cleared
	for scope in appHashes do
		if scopes[scope] == nil then
			scopes[scope] = {}
		end
	end

	local changed = false
	for scope, list in scopes do
		local guildId = if scope == "global" then nil else scope
		local hash = crypto.hash("sha256", json.encode(list), "hex")
		if force or appHashes[scope] ~= hash then
			local result, err = self.api.commands.set(list, guildId)
			if result == nil then
				log(`syncing commands ({scope}) failed: {tostring(err)}`)
			else
				log(`synced {#list} command(s) to {if guildId then "guild " .. guildId else "global scope"}`)
				for _, cmd in result do
					if cmd.type == 1 then
						self.commandIds[cmd.name] = cmd.id
					end
				end
				appHashes[scope] = if #list > 0 then hash else nil
				changed = true
			end
		else
			-- unchanged; still learn the ids for mentions
			local existing = self.api.commands.list(guildId)
			for _, cmd in existing or {} do
				if cmd.type == 1 then
					self.commandIds[cmd.name] = cmd.id
				end
			end
		end
	end

	if changed and cacheFile then
		hashes[self.applicationId] = appHashes
		local ok, err = pcall(fs.writeFile, cacheFile, json.encode(hashes, { indent = 2 }))
		if not ok then
			log("couldn't write the command cache:", err)
		end
	end
end

-- removes every command in a scope (a guild id, or nil for global)
function Bot:clearCommands(guildId: string?)
	return self.api.commands.set({}, guildId)
end

-- running ------------------------------------------------------------------------------------

--[[
	Serves interactions over HTTP instead of (or as well as) the gateway. Call before `run`.
	options: { publicKey, port = 8080, host, path = "/interactions" }
]]
function Bot:listen(options: any): any
	local listen = require("./http")
	options = table.clone(options or {})
	if options.publicKey == nil then
		-- the application's public key, as shown in the developer portal
		local app, err = self:application()
		if app == nil or app.verify_key == nil then
			error(`listen: no publicKey given and the application couldn't be fetched ({tostring(err)})`, 2)
		end
		options.publicKey = app.verify_key
	end
	self._server = listen(self, options)
	return self._server
end

-- the application object (cached after the first call)
function Bot:application(refresh: boolean?): (any, any)
	if self._application and not refresh then
		return self._application, nil
	end
	local app, err = self.api.application.me()
	if app then
		self._application = app
		self.applicationId = self.applicationId or app.id
	end
	return app, err
end

-- application flags that mean a privileged intent is enabled in the developer portal
-- https://docs.discord.com/developers/resources/application#application-object-application-flags
local PRIVILEGED_FLAGS = {
	GuildPresences = { 2 ^ 12, 2 ^ 13 },
	GuildMembers = { 2 ^ 14, 2 ^ 15 },
	MessageContent = { 2 ^ 18, 2 ^ 19 },
}

--[[
	Privileged intents the bot asks for but the developer portal doesn't allow. Identifying with
	them makes Discord close the connection (4014), so `run` drops them with a warning unless
	`strictIntents` is set. Returns nil when the application can't be fetched.
]]
function Bot:disallowedIntents(): { string }?
	local app = self:application()
	if app == nil then
		return nil
	end
	local flags = app.flags or 0
	local out = {}
	for _, name in Intent.privilegedIn(self.intents) do
		local allowed = false
		for _, flag in PRIVILEGED_FLAGS[name] or {} do
			if math.floor(flags / flag) % 2 == 1 then
				allowed = true
			end
		end
		if not allowed then
			table.insert(out, name)
		end
	end
	return out
end

-- for HTTP-only bots: learn who we are without a gateway READY
function Bot:_bootstrap()
	local me = self.api.users.me()
	local app = self:application()
	if me == nil or app == nil then
		error("couldn't fetch the bot user/application; is the token right?", 0)
	end
	self:_onReady({ user = me, application = app })
end

--[[
	Connects and blocks until the bot stops. Returns false and a reason when Discord closes the
	connection for good (bad token, disallowed intents...).
	With `gateway = false` in the options, only the HTTP endpoint runs.
]]
function Bot:run(): (boolean, string?)
	if self.options.http then
		self:listen(self.options.http)
	end
	if self.options.gateway == false then
		if self._server == nil then
			error("gateway = false needs an HTTP endpoint: pass http = { publicKey, port } or call bot:listen", 2)
		end
		self:_bootstrap()
		self._server:wait()
		return true, nil
	end
	if not self.options.strictIntents then
		local missing = self:disallowedIntents()
		if missing and #missing > 0 then
			for _, name in missing do
				self.gateway.intents = Intent.remove(self.gateway.intents, name)
			end
			self.intents = self.gateway.intents
			log(`warning: {table.concat(missing, ", ")} isn't enabled for this application (Developer Portal > Bot > Privileged Gateway Intents); connecting without it`)
		end
	end
	local ok, reason = self.gateway:run()
	if not ok then
		log("stopped:", reason)
	end
	return ok, reason
end

-- like run, but exits the process on a fatal close
function Bot:start()
	local ok = self:run()
	if not ok then
		process.exit(1)
	end
end

function Bot:stop()
	self.gateway:stop()
	if self._server then
		self._server:close()
	end
end

-- the commands for a help listing: { name, description, usage, category, kind, aliases }
function Bot:helpEntries(prefix: string?): { any }
	local out = {}
	local p = prefix or (if type(self.options.prefix) == "string" then self.options.prefix else "/")
	for _, def in self.commandList do
		if not def.hidden then
			table.insert(out, {
				name = def.name,
				description = def.description,
				category = def.category or "General",
				kind = def.kind,
				aliases = def.aliases,
				usage = if def.kind == "user" or def.kind == "message" then "(right click > Apps)"
					elseif def.isPrefix then commands.usage(def, p)
					else commands.usage(def, "/"),
				definition = def,
			})
		end
	end
	return out
end

return Bot
