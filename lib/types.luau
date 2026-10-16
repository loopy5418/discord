--[[
	Types for the Luau language server: every definition field, bot option and context member.
]]

--- Anything ctx:reply / ctx:send / ctx:edit accept: a string, a single component or embed, or
--- an options table (see bot/messages.luau).
export type MessageInput = string | {
	content: string?,
	embeds: { any }?,
	embed: any?,
	components: { any }?,
	files: { File }?,
	file: File?,
	ephemeral: boolean?,
	silent: boolean?,
	suppressEmbeds: boolean?,
	tts: boolean?,
	poll: any?,
	stickers: { string }?,
	allowedMentions: (AllowedMentions | false)?,
	reply: (string | { [string]: any })?,
	flags: number?,
	v2: boolean?,
	attachments: { any }?,
	[string]: any,
}

export type File = {
	name: string,
	data: string?,
	path: string?,
	contentType: string?,
	description: string?,
	spoiler: boolean?,
}

export type AllowedMentions = {
	parse: { "users" | "roles" | "everyone" }?,
	users: { string }?,
	roles: { string }?,
	repliedUser: boolean?,
}

export type OptionType =
	"string"
	| "integer"
	| "number"
	| "boolean"
	| "user"
	| "member"
	| "channel"
	| "role"
	| "mentionable"
	| "attachment"

export type Choice = string | number | { name: string, value: string | number, nameLocalizations: { [string]: string }? }

export type OptionDefinition = {
	name: string, -- lowercase, 1-32 characters
	description: string?, -- 1-100 characters
	type: (OptionType | number)?, -- default "string"; "member" resolves to the guild member
	required: boolean?,
	default: any?, -- the value when the option is left out
	choices: { Choice }?, -- at most 25
	min: number?, -- integers/numbers
	max: number?,
	minLength: number?, -- strings
	maxLength: number?,
	channelTypes: { string | number }?, -- "text", "voice", "thread", "forum", ... (enums.ChannelTypeAlias)
	--- a function(ctx, value, optionName) returning choices, or a list to filter by what's typed
	autocomplete: (((Context, any, string) -> { Choice }?) | { Choice })?,
	--- prefix commands: take the rest of the message (default for the last string option)
	rest: boolean?,
	nameLocalizations: { [string]: string }?,
	descriptionLocalizations: { [string]: string }?,
}

export type Cooldown = number | {
	seconds: number,
	scope: ("user" | "guild" | "channel" | "global")?,
	message: string?,
}

export type Check = (Context) -> (boolean | string, string?)

export type CommandDefinition = {
	name: string,
	description: string?,
	--- "slash" (default), "user" / "message" (context menu: right click > Apps), "prefix" (prefix only)
	type: ("slash" | "user" | "message" | "prefix")?,
	--- slash commands: also run as a prefix command (a hybrid). `slash = false` makes it prefix-only.
	prefix: boolean?,
	slash: boolean?,
	aliases: { string }?, -- other prefix names
	options: { OptionDefinition }?,
	--- subcommands; an entry with its own `subcommands` is a group (two levels at most)
	subcommands: { SubcommandDefinition }?,

	--- slash: run(ctx, options); user: run(ctx, targetUser); message: run(ctx, targetMessage);
	--- prefix: run(ctx, args)
	run: ((Context, any) -> ())?,
	autocomplete: ((Context, any, string) -> { Choice }?)?, -- fallback for every autocomplete option

	--- default permissions to see/use it (Discord enforces these for slash/context commands;
	--- they're checked at runtime for prefix commands)
	permissions: { string }?,
	botPermissions: { string }?, -- checked before running
	ownerOnly: boolean?,
	guildOnly: boolean?,
	dmOnly: boolean?,
	nsfw: boolean?,
	--- where the command can be installed: { "guild", "user" } ("user" = user-installed app)
	install: { "guild" | "user" }?,
	--- where it can be used: { "guild", "botDm", "privateChannel" }
	contexts: { "guild" | "botDm" | "privateChannel" }?,
	guilds: { string }?, -- register only in these guilds instead of globally
	cooldown: Cooldown?,
	checks: { Check }?, -- return true, or false and a message (or just a message)
	ephemeral: boolean?, -- replies default to ephemeral
	defer: (boolean | "ephemeral")?, -- defer before running (for slow commands)

	nameLocalizations: { [string]: string }?,
	descriptionLocalizations: { [string]: string }?,
	-- free-form metadata, e.g. for help commands
	category: string?,
	usage: string?,
	examples: { string }?,
	hidden: boolean?, -- left out of bot:helpEntries()
	[string]: any,
}

export type SubcommandDefinition = {
	name: string,
	description: string?,
	options: { OptionDefinition }?,
	subcommands: { SubcommandDefinition }?,
	aliases: { string }?,
	run: ((Context, { [string]: any }) -> ())?,
	permissions: { string }?,
	botPermissions: { string }?,
	ownerOnly: boolean?,
	cooldown: Cooldown?,
	checks: { Check }?,
	ephemeral: boolean?,
	defer: (boolean | "ephemeral")?,
	[string]: any,
}

export type ComponentDefinition = {
	--- the name before the first ":" of the custom id ("vote" handles "vote:yes" and "vote:no")
	customId: (string | { string })?,
	match: string?, -- or a Lua pattern on the whole custom id; captures become the params
	--- run(ctx, ...params); read ctx.values for selects
	run: (Context, ...string) -> (),
	defer: (boolean | "update" | "reply" | "ephemeral")?,
	ephemeral: boolean?,
	permissions: { string }?,
	botPermissions: { string }?,
	ownerOnly: boolean?,
	cooldown: Cooldown?,
	checks: { Check }?,
	[string]: any,
}

export type ModalDefinition = {
	customId: (string | { string })?,
	match: string?,
	--- run(ctx, fields): fields maps input custom ids to values
	run: (Context, { [string]: any }) -> (),
	defer: (boolean | "update" | "reply" | "ephemeral")?,
	ephemeral: boolean?,
	checks: { Check }?,
	[string]: any,
}

export type EventDefinition = {
	event: string, -- "MESSAGE_CREATE" or "messageCreate"; "*" for everything
	once: boolean?,
	run: (Context, any) -> (),
}

export type BotOptions = {
	token: string?, -- default: the DISCORD_TOKEN environment variable
	intents: ({ string } | number)?, -- default Guilds, GuildMessages, DirectMessages (+ MessageContent with a prefix)
	presence: { [string]: any }?,
	--- prefix(es) for prefix commands, or a function(message, bot) returning them (may yield)
	prefix: (string | { string } | (any, any) -> (string | { string })?)?,
	mentionPrefix: boolean?, -- "@bot ping" works (default true)
	caseInsensitive: boolean?, -- prefix and command names (default true)
	ignoreBots: boolean?, -- default true
	owners: { string }?, -- default: the application's owner / team
	devGuild: string?, -- register every command in this guild (instant updates while developing)
	syncCommands: (boolean | "force")?, -- default true: sync changed commands on READY
	commandCache: string?, -- where command hashes are kept (default <project>/.commands.lock.json)
	defaultInstall: { "guild" | "user" }?, -- `install` for commands that don't set it
	defaultContexts: { "guild" | "botDm" | "privateChannel" }?,
	allowedMentions: AllowedMentions?, -- default { parse = { "users" }, repliedUser = false }
	autoDefer: boolean?, -- defer commands that haven't answered after ~2.3s (default true)
	errorMessage: (string | false)?, -- shown when a handler errors
	cache: boolean?, -- default true
	applicationId: string?, -- learned on READY otherwise
	http: { publicKey: string?, port: number?, host: string?, path: string? }?, -- HTTP interactions (publicKey defaults to the application's)
	gateway: boolean?, -- false: HTTP interactions only
	--- built programs: lists the asset files under a folder, for bot:load. Write it in your own
	--- code: `function(folder) return pocket.list(folder) end` (default: the root project's assets)
	assets: ((folder: string) -> { string })?,
	strictIntents: boolean?, -- don't drop privileged intents the developer portal hasn't enabled
	debug: boolean?, -- print gateway payloads
	debugRest: boolean?, -- print REST calls
}

--[[
	The context every handler gets as its first argument.

	Which fields are set depends on `kind`:
	- "slash":        options, args, commandName, commandPath, subcommand, group
	- "user":         target (user), targetMember, targetId
	- "message":      target (message), targetId
	- "prefix":       message, content, prefix, invokedWith, args/options, rawArgs, argText
	- "component":    customId, name, params, values, componentType, message, resolved
	- "modal":        customId, name, params, fields, message (if opened from a component)
	- "autocomplete": options, focused { name, value, type }
	- "event":        event, eventData (and message/user when the event has them)
]]
export type Context = {
	-- libraries and shared objects
	bot: any,
	api: any, -- endpoint wrappers: api.channels, api.guilds, api.users, api.interactions, ...
	rest: any, -- raw REST: rest:request(method, route, options)
	cache: any,
	ui: any, -- component builders (bot/components.luau)
	fmt: any, -- markdown/mention helpers (bot/format.luau)
	enums: any,
	permissions: any,
	store: { [string]: any }, -- shared across every handler for the bot's lifetime
	state: { [string]: any }, -- scratch space for this one invocation (middleware can fill it)

	-- what this is
	kind: "slash" | "user" | "message" | "prefix" | "component" | "modal" | "autocomplete" | "event",
	isInteraction: boolean,
	isPrefix: boolean,
	createdAt: number,

	-- who and where
	user: any, -- the user who triggered this
	author: any, -- same as user
	member: any?, -- their guild member (with .permissions on interactions)
	guildId: string?,
	channelId: string?,
	channel: any?, -- the partial channel sent with interactions
	inGuild: boolean,
	inDM: boolean,
	where: string?, -- "guild" | "botDm" | "privateChannel"
	locale: string?, -- the user's language (interactions)
	guildLocale: string?,
	isUserInstall: boolean, -- run through a user-installed app
	isGuildInstall: boolean,
	botPresent: boolean, -- whether the bot can make normal API calls here (false for user installs in foreign servers)
	authorizingOwners: { [string]: string }?,
	appPermissions: string?, -- the bot's permissions here (interactions)
	entitlements: { any }?,

	-- interaction data
	interaction: any?,
	id: string?,
	token: string?,
	data: any?,
	message: any?, -- prefix: the command message; component: the message it's on
	content: string?,

	-- commands
	command: CommandDefinition?,
	commandName: string?,
	commandPath: string?, -- "config set"
	subcommand: string?,
	group: string?,
	options: { [string]: any }?,
	args: { [string]: any }?,
	rawArgs: { string }?, -- prefix: the words after the command
	argText: string?, -- prefix: everything after the command name
	prefix: string?,
	invokedWith: string?, -- prefix: the name or alias used
	target: any?, -- context menus
	targetMember: any?,
	targetId: string?,
	focused: { name: string, value: any, type: number }?, -- autocomplete

	-- components and modals
	customId: string?,
	name: string?, -- the custom id before the first ":"
	params: { string }?, -- the parts after it
	values: { string }?, -- select menu values
	componentType: number?,
	fields: { [string]: any }?, -- modal values by custom id
	resolved: any?,

	-- events
	event: string?,
	eventData: any?,

	-- response state
	responded: boolean,
	deferred: boolean,
	replied: boolean,
	ephemeral: boolean?,
	ephemeralDefault: boolean?,
	replyMessage: any?,

	-- responding
	reply: (self: Context, input: MessageInput) -> (any, any),
	followUp: (self: Context, input: MessageInput) -> (any, any),
	defer: (self: Context, options: { ephemeral: boolean? }?) -> (any, any),
	deferUpdate: (self: Context) -> (any, any),
	update: (self: Context, input: MessageInput) -> (any, any),
	edit: (self: Context, input: MessageInput) -> (any, any),
	editReply: (self: Context, input: MessageInput) -> (any, any),
	deleteReply: (self: Context) -> (any, any),
	fetchReply: (self: Context) -> (any, any),
	send: (self: Context, input: MessageInput) -> (any, any),
	showModal: (self: Context, modal: any) -> (any, any),
	prompt: (self: Context, modal: any, timeout: number?) -> Context?,
	respond: (self: Context, choices: { Choice }) -> (any, any),
	error: (self: Context, text: string) -> (any, any),
	fail: (self: Context, text: string) -> (any, any),

	-- messages
	react: (self: Context, emoji: any, messageId: string?) -> (any, any),
	typing: (self: Context) -> (any, any),
	dm: (self: Context, input: MessageInput, userId: string?) -> (any, any),

	-- waiting
	awaitComponent: (self: Context, options: { [string]: any }?) -> Context?,
	collect: (self: Context, options: { [string]: any }, handler: (Context) -> ()) -> { stop: () -> (), count: () -> number },
	awaitMessage: (self: Context, options: { [string]: any }?) -> any?,
	waitFor: (self: Context, event: string, filter: ((any) -> boolean)?, timeout: number?) -> any?,
	confirm: (self: Context, question: MessageInput, options: { [string]: any }?) -> boolean?,
	paginate: (self: Context, pages: { MessageInput }, options: { [string]: any }?) -> (),

	-- permissions
	memberPermissions: (self: Context) -> number,
	botPermissions: (self: Context) -> number,
	hasPermission: (self: Context, perms: any) -> (boolean, { string }),
	botHasPermission: (self: Context, perms: any) -> (boolean, { string }),
	isOwner: (self: Context, userId: string?) -> boolean,

	-- lookups
	fetchGuild: (self: Context) -> any?,
	fetchChannel: (self: Context, channelId: string?) -> any?,
	fetchMember: (self: Context, userId: string?) -> any?,
	fetchUser: (self: Context, userId: string) -> any?,
	fetchRole: (self: Context, idOrName: string) -> any?,

	-- conveniences
	getOption: (self: Context, name: string, default: any?) -> any,
	field: (self: Context, customId: string, default: any?) -> any,
	mention: (self: Context) -> string,
	displayName: (self: Context, user: any?, member: any?) -> string,
	latency: (self: Context) -> number?,
	sleep: (self: Context, seconds: number?) -> number,
	spawn: (self: Context, fn: (...any) -> ...any, ...any) -> thread,
	log: (self: Context, ...any) -> (),
	commandMention: (self: Context, name: string) -> string,
	is: (self: Context, name: string) -> boolean,
	selected: (self: Context) -> { any },
	uploads: (self: Context, customId: string) -> { any },
	findComponent: (self: Context, customId: string) -> any?,

	[string]: any,
}

return {}
