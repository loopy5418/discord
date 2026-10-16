--[[
	In-memory cache for gateway events (so that the bot doesn't have to do
	a REST lookup every time you want to get a server or member or message)

	    bot.cache.guilds[id], bot.cache.channels[id], bot.cache.users[id]
	    bot.cache:member(guildId, userId)
]]

local Cache = {}
Cache.__index = Cache

function Cache.new()
	return setmetatable({
		guilds = {} :: { [string]: any }, -- guild object; guild.roles is a list
		channels = {} :: { [string]: any }, -- guild channels, threads and DMs
		users = {} :: { [string]: any },
		members = {} :: { [string]: { [string]: any } }, -- guildId -> userId -> member
		enabled = true,
	}, Cache)
end

function Cache:user(id: string): any
	return self.users[id]
end

function Cache:member(guildId: string, userId: string): any
	local list = self.members[guildId]
	return list and list[userId]
end

function Cache:channel(id: string): any
	return self.channels[id]
end

function Cache:guild(id: string): any
	return self.guilds[id]
end

function Cache:role(guildId: string, roleId: string): any
	local guild = self.guilds[guildId]
	if guild == nil then
		return nil
	end
	for _, role in guild.roles or {} do
		if role.id == roleId then
			return role
		end
	end
	return nil
end

function Cache:putUser(user: any)
	if user and user.id then
		local existing = self.users[user.id]
		if existing then
			-- replace in place so held references stay live; absent fields were null
			table.clear(existing)
			for k, v in user do
				existing[k] = v
			end
		else
			self.users[user.id] = table.clone(user)
		end
	end
end

-- members arrive without user objects inside interactions/messages; pass the user id
function Cache:putMember(guildId: string, member: any, userId: string?)
	if member == nil then
		return
	end
	local id = userId or (member.user and member.user.id)
	if id == nil then
		return
	end
	if member.user then
		self:putUser(member.user)
	end
	local list = self.members[guildId]
	if list == nil then
		list = {}
		self.members[guildId] = list
	end
	local entry = table.clone(member)
	entry.user = nil
	-- interaction members carry computed permissions, which go stale; drop them
	entry.permissions = nil
	list[id] = entry
end

function Cache:putChannel(channel: any, guildId: string?)
	if channel and channel.id then
		if guildId and channel.guild_id == nil then
			channel.guild_id = guildId
		end
		self.channels[channel.id] = channel
	end
end

local function upsertRole(guild: any, role: any)
	guild.roles = guild.roles or {}
	for i, r in guild.roles do
		if r.id == role.id then
			guild.roles[i] = role
			return
		end
	end
	table.insert(guild.roles, role)
end

-- guild fields Discord sends in GUILD_CREATE but not in GUILD_UPDATE
local CREATE_ONLY = {
	joined_at = true,
	large = true,
	member_count = true,
	stage_instances = true,
	guild_scheduled_events = true,
	soundboard_sounds = true,
}

-- applies a gateway dispatch
function Cache:handle(event: string, d: any)
	if not self.enabled or type(d) ~= "table" then
		return
	end
	if event == "GUILD_CREATE" or event == "GUILD_UPDATE" then
		if d.unavailable then
			return
		end
		local guild = self.guilds[d.id] or {}
		-- a field missing from the update was nulled, unless it only ever comes with GUILD_CREATE
		for k in guild do
			if d[k] == nil and not CREATE_ONLY[k] then
				guild[k] = nil
			end
		end
		for k, v in d do
			if k ~= "channels" and k ~= "threads" and k ~= "members" and k ~= "presences" and k ~= "voice_states" then
				guild[k] = v
			end
		end
		self.guilds[d.id] = guild
		for _, channel in d.channels or {} do
			self:putChannel(channel, d.id)
		end
		for _, thread in d.threads or {} do
			self:putChannel(thread, d.id)
		end
		for _, member in d.members or {} do
			self:putMember(d.id, member)
		end
	elseif event == "GUILD_DELETE" then
		if not d.unavailable then
			self.guilds[d.id] = nil
			self.members[d.id] = nil
			for id, channel in self.channels do
				if channel.guild_id == d.id then
					self.channels[id] = nil
				end
			end
		end
	elseif event == "GUILD_ROLE_CREATE" or event == "GUILD_ROLE_UPDATE" then
		local guild = self.guilds[d.guild_id]
		if guild then
			upsertRole(guild, d.role)
		end
	elseif event == "GUILD_ROLE_DELETE" then
		local guild = self.guilds[d.guild_id]
		if guild and guild.roles then
			for i, r in guild.roles do
				if r.id == d.role_id then
					table.remove(guild.roles, i)
					break
				end
			end
		end
	elseif event == "CHANNEL_CREATE" or event == "CHANNEL_UPDATE" or event == "THREAD_CREATE" or event == "THREAD_UPDATE" then
		self:putChannel(d, d.guild_id)
	elseif event == "CHANNEL_DELETE" or event == "THREAD_DELETE" then
		self.channels[d.id] = nil
	elseif event == "THREAD_LIST_SYNC" then
		for _, thread in d.threads or {} do
			self:putChannel(thread, d.guild_id)
		end
	elseif event == "GUILD_MEMBER_ADD" or event == "GUILD_MEMBER_UPDATE" then
		self:putMember(d.guild_id, d)
	elseif event == "GUILD_MEMBER_REMOVE" then
		local list = self.members[d.guild_id]
		if list and d.user then
			list[d.user.id] = nil
		end
	elseif event == "GUILD_MEMBERS_CHUNK" then
		for _, member in d.members or {} do
			self:putMember(d.guild_id, member)
		end
	elseif event == "MESSAGE_CREATE" then
		self:putUser(d.author)
		if d.guild_id and d.member and d.author then
			self:putMember(d.guild_id, d.member, d.author.id)
		end
		for _, user in d.mentions or {} do
			self:putUser(user)
			if d.guild_id and user.member then
				self:putMember(d.guild_id, user.member, user.id)
			end
		end
	elseif event == "USER_UPDATE" then
		self:putUser(d)
	elseif event == "INTERACTION_CREATE" then
		local user = d.user or (d.member and d.member.user)
		self:putUser(user)
		if d.guild_id and d.member and user then
			self:putMember(d.guild_id, d.member, user.id)
		end
	end
end

function Cache:clear()
	table.clear(self.guilds)
	table.clear(self.channels)
	table.clear(self.users)
	table.clear(self.members)
end

return Cache
