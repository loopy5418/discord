--[[
    Intents
]]

export type IntentName =
	"Guilds"
	| "GuildMembers"
	| "GuildModeration"
	| "GuildExpressions"
	| "GuildIntegrations"
	| "GuildWebhooks"
	| "GuildInvites"
	| "GuildVoiceStates"
	| "GuildPresences"
	| "GuildMessages"
	| "GuildMessageReactions"
	| "GuildMessageTyping"
	| "DirectMessages"
	| "DirectMessageReactions"
	| "DirectMessageTyping"
	| "MessageContent"
	| "GuildScheduledEvents"
	| "AutoModerationConfiguration"
	| "AutoModerationExecution"
	| "GuildMessagePolls"
	| "DirectMessagePolls"

-- what users may pass in bot options
export type IntentInput = number | { IntentName | number }

local Intent = {}

-- bit positions from the Discord gateway docs
-- https://docs.discord.com/developers/events/gateway#list-of-intents
local bits: { [IntentName]: number } = {
	Guilds = 0,
	GuildMembers = 1, -- privileged
	GuildModeration = 2,
	GuildExpressions = 3,
	GuildIntegrations = 4,
	GuildWebhooks = 5,
	GuildInvites = 6,
	GuildVoiceStates = 7,
	GuildPresences = 8, -- privileged
	GuildMessages = 9,
	GuildMessageReactions = 10,
	GuildMessageTyping = 11,
	DirectMessages = 12,
	DirectMessageReactions = 13,
	DirectMessageTyping = 14,
	MessageContent = 15, -- privileged
	GuildScheduledEvents = 16,
	AutoModerationConfiguration = 20,
	AutoModerationExecution = 21,
	GuildMessagePolls = 24,
	DirectMessagePolls = 25,
}

-- privileged intents must be enabled in the developer portal
local privileged: { [IntentName]: boolean } = {
	GuildMembers = true,
	GuildPresences = true,
	MessageContent = true,
}

-- flag values, e.g. Intent.Flags.Guilds == 1
local flags: { [IntentName]: number } = {}
for name, bit in bits do
	flags[name] = bit32.lshift(1, bit)
end
Intent.Flags = table.freeze(flags)

-- which intents deliver each gateway event (any one of them is enough), so the bot can warn
-- when you register a handler for an event you will never receive.
-- https://docs.discord.com/developers/events/gateway#list-of-intents
local eventRequires: { [string]: { IntentName } } = {}
local function events(intents: { IntentName }, names: { string })
	for _, event in names do
		local list = eventRequires[event] or {}
		for _, intent in intents do
			if not table.find(list, intent) then
				table.insert(list, intent)
			end
		end
		eventRequires[event] = list
	end
end

events({ "Guilds" }, {
	"GUILD_CREATE", "GUILD_UPDATE", "GUILD_DELETE",
	"GUILD_ROLE_CREATE", "GUILD_ROLE_UPDATE", "GUILD_ROLE_DELETE",
	"CHANNEL_CREATE", "CHANNEL_UPDATE", "CHANNEL_DELETE",
	"THREAD_CREATE", "THREAD_UPDATE", "THREAD_DELETE", "THREAD_LIST_SYNC",
	"THREAD_MEMBER_UPDATE", "THREAD_MEMBERS_UPDATE", -- THREAD_MEMBERS_UPDATE has more data with GuildMembers
	"STAGE_INSTANCE_CREATE", "STAGE_INSTANCE_UPDATE", "STAGE_INSTANCE_DELETE",
	"VOICE_CHANNEL_STATUS_UPDATE", "VOICE_CHANNEL_START_TIME_UPDATE",
})
events({ "Guilds", "DirectMessages" }, { "CHANNEL_PINS_UPDATE" })
events({ "GuildMembers" }, { "GUILD_MEMBER_ADD", "GUILD_MEMBER_UPDATE", "GUILD_MEMBER_REMOVE" })
events({ "GuildModeration" }, { "GUILD_AUDIT_LOG_ENTRY_CREATE", "GUILD_BAN_ADD", "GUILD_BAN_REMOVE" })
events({ "GuildExpressions" }, {
	"GUILD_EMOJIS_UPDATE", "GUILD_STICKERS_UPDATE",
	"GUILD_SOUNDBOARD_SOUND_CREATE", "GUILD_SOUNDBOARD_SOUND_UPDATE", "GUILD_SOUNDBOARD_SOUND_DELETE",
	"GUILD_SOUNDBOARD_SOUNDS_UPDATE",
})
events({ "GuildIntegrations" }, {
	"GUILD_INTEGRATIONS_UPDATE", "INTEGRATION_CREATE", "INTEGRATION_UPDATE", "INTEGRATION_DELETE",
})
events({ "GuildWebhooks" }, { "WEBHOOKS_UPDATE" })
events({ "GuildInvites" }, { "INVITE_CREATE", "INVITE_DELETE" })
events({ "GuildVoiceStates" }, { "VOICE_CHANNEL_EFFECT_SEND", "VOICE_STATE_UPDATE" })
events({ "GuildPresences" }, { "PRESENCE_UPDATE" })
events({ "GuildMessages", "DirectMessages" }, { "MESSAGE_CREATE", "MESSAGE_UPDATE", "MESSAGE_DELETE" })
events({ "GuildMessages" }, { "MESSAGE_DELETE_BULK" })
events({ "GuildMessageReactions", "DirectMessageReactions" }, {
	"MESSAGE_REACTION_ADD", "MESSAGE_REACTION_REMOVE",
	"MESSAGE_REACTION_REMOVE_ALL", "MESSAGE_REACTION_REMOVE_EMOJI",
})
events({ "GuildMessageTyping", "DirectMessageTyping" }, { "TYPING_START" })
events({ "GuildScheduledEvents" }, {
	"GUILD_SCHEDULED_EVENT_CREATE", "GUILD_SCHEDULED_EVENT_UPDATE", "GUILD_SCHEDULED_EVENT_DELETE",
	"GUILD_SCHEDULED_EVENT_USER_ADD", "GUILD_SCHEDULED_EVENT_USER_REMOVE",
})
events({ "AutoModerationConfiguration" }, {
	"AUTO_MODERATION_RULE_CREATE", "AUTO_MODERATION_RULE_UPDATE", "AUTO_MODERATION_RULE_DELETE",
})
events({ "AutoModerationExecution" }, { "AUTO_MODERATION_ACTION_EXECUTION" })
events({ "GuildMessagePolls", "DirectMessagePolls" }, { "MESSAGE_POLL_VOTE_ADD", "MESSAGE_POLL_VOTE_REMOVE" })

for _, list in eventRequires do
	table.freeze(list)
end
Intent.EventRequires = table.freeze(eventRequires)

-- MessageContent doesntt deliver events of its own: without it, content, embeds, attachments,
-- components and poll are empty on messages, except in DMs, messages that mention the bot,
-- and the bot's own messages.

-- Sensible default: enough for slash commands and basic message events,
-- with no privileged intents.
Intent.Default = bit32.bor(Intent.Flags.Guilds, Intent.Flags.GuildMessages)

-- everything non-privileged
local nonPrivileged = 0
for name, value in Intent.Flags do
	if not privileged[name] then
		nonPrivileged = bit32.bor(nonPrivileged, value)
	end
end
Intent.NonPrivileged = nonPrivileged

-- turn user input into a final mask. errors on unknown names so a typo
-- fails at startup instead of silently dropping events.
function Intent.resolve(input: IntentInput?): number
	if input == nil then
		return Intent.Default
	end
	if type(input) == "number" then
		return input
	end

	local mask = 0
	for _, item in input do
		if type(item) == "number" then
			mask = bit32.bor(mask, item)
		else
			local value = Intent.Flags[item]
			if value == nil then
				error(`unknown intent "{item}"`, 2)
			end
			mask = bit32.bor(mask, value)
		end
	end
	return mask
end

function Intent.has(mask: number, name: IntentName): boolean
	local value = Intent.Flags[name]
	return value ~= nil and bit32.band(mask, value) ~= 0
end

function Intent.add(mask: number, name: IntentName): number
	return bit32.bor(mask, Intent.Flags[name])
end

function Intent.remove(mask: number, name: IntentName): number
	return bit32.band(mask, bit32.bnot(Intent.Flags[name]))
end

-- whether a mask receives "event". Events no intent controls (READY, INTERACTION_CREATE, ...)
-- always arrive. Also returns the intents that would deliver it
function Intent.receives(mask: number, event: string): (boolean, { IntentName }?)
	local needed = Intent.EventRequires[event]
	if needed == nil then
		return true, nil
	end
	for _, name in needed do
		if Intent.has(mask, name) then
			return true, needed
		end
	end
	return false, needed
end

-- names contained in a mask, sorted for stable output
function Intent.names(mask: number): { IntentName }
	local out: { IntentName } = {}
	for name, value in Intent.Flags do
		if bit32.band(mask, value) ~= 0 then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

-- wrivileged intents in a mask, so the bot can print a clear startup
-- warning pointing at the developer portal
function Intent.privilegedIn(mask: number): { IntentName }
	local out: { IntentName } = {}
	for _, name in Intent.names(mask) do
		if privileged[name] then
			table.insert(out, name)
		end
	end
	return out
end

return table.freeze(Intent)