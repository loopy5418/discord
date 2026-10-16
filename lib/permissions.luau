--[[
	Permissions

	Discord permissions are a bitfield wider than 32 bits, sent as a decimal string, so bit32
	can't hold them. They're kept as plain numbers here (exact up to 2^53) and combined with
	arithmetic instead.

	    local Permissions = require("@discord/lib/permissions")
	    local mask = Permissions.resolve({ "BanMembers", "KickMembers" })
	    Permissions.has(member.permissions, "BanMembers")
]]

local Permissions = {}

-- bit positions
-- https://docs.discord.com/developers/topics/permissions#permissions-bitwise-permission-flags
local bits = {
	CreateInstantInvite = 0,
	KickMembers = 1,
	BanMembers = 2,
	Administrator = 3,
	ManageChannels = 4,
	ManageGuild = 5,
	AddReactions = 6,
	ViewAuditLog = 7,
	PrioritySpeaker = 8,
	Stream = 9,
	ViewChannel = 10,
	SendMessages = 11,
	SendTTSMessages = 12,
	ManageMessages = 13,
	EmbedLinks = 14,
	AttachFiles = 15,
	ReadMessageHistory = 16,
	MentionEveryone = 17,
	UseExternalEmojis = 18,
	ViewGuildInsights = 19,
	Connect = 20,
	Speak = 21,
	MuteMembers = 22,
	DeafenMembers = 23,
	MoveMembers = 24,
	UseVAD = 25,
	ChangeNickname = 26,
	ManageNicknames = 27,
	ManageRoles = 28,
	ManageWebhooks = 29,
	ManageGuildExpressions = 30,
	UseApplicationCommands = 31,
	RequestToSpeak = 32,
	ManageEvents = 33,
	ManageThreads = 34,
	CreatePublicThreads = 35,
	CreatePrivateThreads = 36,
	UseExternalStickers = 37,
	SendMessagesInThreads = 38,
	UseEmbeddedActivities = 39,
	ModerateMembers = 40,
	ViewCreatorMonetizationAnalytics = 41,
	UseSoundboard = 42,
	CreateGuildExpressions = 43,
	CreateEvents = 44,
	UseExternalSounds = 45,
	SendVoiceMessages = 46,
	SendPolls = 49,
	UseExternalApps = 50,
	PinMessages = 51,
	BypassSlowmode = 52,
}

local flags = {}
for name, bit in bits do
	flags[name] = 2 ^ bit
end
Permissions.Flags = table.freeze(flags)

local ALL = 0
for _, value in flags do
	ALL += value
end
Permissions.All = ALL

local function toNumber(value: any): number
	if type(value) == "number" then
		return value
	elseif type(value) == "string" then
		return tonumber(value) or 0
	end
	return 0
end

local function hasBit(mask: number, flag: number): boolean
	return math.floor(mask / flag) % 2 == 1
end

local function lookup(name: string): number
	local value = flags[name]
	if value == nil then
		-- forgiving: "ban_members", "BAN_MEMBERS", "banmembers"
		local wanted = string.lower((string.gsub(name, "_", "")))
		for key, v in flags do
			if string.lower(key) == wanted then
				return v
			end
		end
		error(`unknown permission "{name}"`, 3)
	end
	return value
end

-- names, flags, decimal strings or a list of them -> one mask
function Permissions.resolve(input: any): number
	if input == nil then
		return 0
	elseif type(input) == "number" then
		return input
	elseif type(input) == "string" then
		local n = tonumber(input)
		if n then
			return n
		end
		return lookup(input)
	end
	local mask = 0
	for _, item in input do
		mask = Permissions.add(mask, Permissions.resolve(item))
	end
	return mask
end

-- the set bits of `b` that aren't in `a` are added
function Permissions.add(a: any, b: any): number
	local x, y = toNumber(a), toNumber(b)
	local out = x
	local flag = 1
	while flag <= y do
		if hasBit(y, flag) and not hasBit(x, flag) then
			out += flag
		end
		flag *= 2
	end
	return out
end

function Permissions.remove(a: any, b: any): number
	local x, y = toNumber(a), toNumber(b)
	local out = x
	local flag = 1
	while flag <= y do
		if hasBit(y, flag) and hasBit(x, flag) then
			out -= flag
		end
		flag *= 2
	end
	return out
end

-- whether `mask` has every permission in `wanted`. Administrator implies everything.
function Permissions.has(mask: any, wanted: any, ignoreAdmin: boolean?): boolean
	local m = toNumber(mask)
	if not ignoreAdmin and hasBit(m, flags.Administrator) then
		return true
	end
	local w = Permissions.resolve(wanted)
	local flag = 1
	while flag <= w do
		if hasBit(w, flag) and not hasBit(m, flag) then
			return false
		end
		flag *= 2
	end
	return true
end

-- the names of the permissions in `wanted` that `mask` lacks
function Permissions.missing(mask: any, wanted: any): { string }
	local out = {}
	if Permissions.has(mask, flags.Administrator, true) then
		return out
	end
	for _, name in Permissions.names(Permissions.resolve(wanted)) do
		if not Permissions.has(mask, flags[name], true) then
			table.insert(out, name)
		end
	end
	return out
end

-- every permission name in a mask, sorted
function Permissions.names(mask: any): { string }
	local m = toNumber(mask)
	local out = {}
	for name, value in flags do
		if hasBit(m, value) then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

-- the string form Discord expects (no exponent or decimals)
function Permissions.toString(mask: any): string
	return string.format("%.0f", toNumber(mask))
end

-- "BanMembers" -> "Ban Members", for error messages
function Permissions.label(name: string): string
	return (string.gsub(name, "(%l)(%u)", "%1 %2"))
end

--[[
	Works out a member's permissions the way Discord does: @everyone, then roles, then (with a
	channel) the channel's overwrites. `guild` needs `owner_id` and `roles`; `member` needs `roles`
	and the user id.
	https://docs.discord.com/developers/topics/permissions#permission-overwrites
]]
function Permissions.compute(guild: any, member: any, userId: string, channel: any?): number
	if guild == nil or member == nil then
		return 0
	end
	if guild.owner_id == userId then
		return ALL
	end

	local rolesById = {}
	for _, role in guild.roles or {} do
		rolesById[role.id] = role
	end

	local everyone = rolesById[guild.id]
	local base = if everyone then toNumber(everyone.permissions) else 0
	for _, roleId in member.roles or {} do
		local role = rolesById[roleId]
		if role then
			base = Permissions.add(base, role.permissions)
		end
	end
	if hasBit(base, flags.Administrator) then
		return ALL
	end
	if channel == nil or channel.permission_overwrites == nil then
		return base
	end

	local perms = base
	local overwrites = {}
	for _, ow in channel.permission_overwrites do
		overwrites[ow.id] = ow
	end
	-- @everyone overwrite
	local ow = overwrites[guild.id]
	if ow then
		perms = Permissions.remove(perms, ow.deny)
		perms = Permissions.add(perms, ow.allow)
	end
	-- role overwrites, denies before allows
	local allow, deny = 0, 0
	for _, roleId in member.roles or {} do
		local rw = overwrites[roleId]
		if rw then
			allow = Permissions.add(allow, rw.allow)
			deny = Permissions.add(deny, rw.deny)
		end
	end
	perms = Permissions.remove(perms, deny)
	perms = Permissions.add(perms, allow)
	-- member overwrite
	local mw = overwrites[userId]
	if mw then
		perms = Permissions.remove(perms, mw.deny)
		perms = Permissions.add(perms, mw.allow)
	end
	return perms
end

return table.freeze(Permissions)
