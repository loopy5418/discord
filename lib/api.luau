--[[
	Endpoint wrappers, grouped by resource

	Made by Claude because i am not porting allat
]]

local json = require("@sonata/json")
local Rest = require("./rest")
local messages = require("./messages")
local ui = require("./components")
local Permissions = require("./permissions")

local enc = Rest.encodeComponent

-- reaction emoji in URL form: "👍" -> "%F0%9F%91%8D", "<:name:id>" -> "name:id"
local function reactionEmoji(emoji: any): string
	local e = ui.emoji(emoji)
	if e.id then
		return enc(`{e.name or "_"}:{e.id}`)
	end
	return enc(e.name)
end

return function(rest: any, bot: any?)
	local api = {}

	local function defaults()
		if bot then
			return { allowedMentions = bot.options.allowedMentions }
		end
		return nil
	end

	local function sendTo(route: string, input: any, forEdit: boolean?, method: string?)
		local body, files = messages.build(input, defaults(), forEdit)
		return rest:request(method or (if forEdit then "PATCH" else "POST"), route, { body = body, files = files })
	end
	api._sendTo = sendTo

	-- channels and messages ------------------------------------------------------------------

	local channels = {}
	api.channels = channels

	function channels.get(channelId: string)
		return rest:get(`/channels/{channelId}`)
	end

	-- fields: name, topic, nsfw, rate_limit_per_user, parent_id, position, permission_overwrites, ...
	function channels.edit(channelId: string, fields: { [string]: any }, reason: string?)
		return rest:patch(`/channels/{channelId}`, fields, { reason = reason })
	end

	function channels.delete(channelId: string, reason: string?)
		return rest:delete(`/channels/{channelId}`, { reason = reason })
	end

	function channels.send(channelId: string, message: any)
		return sendTo(`/channels/{channelId}/messages`, message)
	end

	function channels.message(channelId: string, messageId: string)
		return rest:get(`/channels/{channelId}/messages/{messageId}`)
	end

	-- options: limit (1-100), before, after, around
	function channels.messages(channelId: string, options: { [string]: any }?)
		return rest:get(`/channels/{channelId}/messages`, { query = options })
	end

	function channels.editMessage(channelId: string, messageId: string, message: any)
		return sendTo(`/channels/{channelId}/messages/{messageId}`, message, true)
	end

	function channels.deleteMessage(channelId: string, messageId: string, reason: string?)
		return rest:delete(`/channels/{channelId}/messages/{messageId}`, { reason = reason })
	end

	-- 2-100 messages younger than two weeks
	function channels.bulkDelete(channelId: string, messageIds: { string }, reason: string?)
		return rest:post(`/channels/{channelId}/messages/bulk-delete`, { messages = messageIds }, { reason = reason })
	end

	function channels.crosspost(channelId: string, messageId: string)
		return rest:post(`/channels/{channelId}/messages/{messageId}/crosspost`)
	end

	function channels.react(channelId: string, messageId: string, emoji: any)
		return rest:put(`/channels/{channelId}/messages/{messageId}/reactions/{reactionEmoji(emoji)}/@me`)
	end

	-- removes the bot's reaction, or `userId`'s
	function channels.unreact(channelId: string, messageId: string, emoji: any, userId: string?)
		return rest:delete(`/channels/{channelId}/messages/{messageId}/reactions/{reactionEmoji(emoji)}/{userId or "@me"}`)
	end

	function channels.reactions(channelId: string, messageId: string, emoji: any, options: { [string]: any }?)
		return rest:get(`/channels/{channelId}/messages/{messageId}/reactions/{reactionEmoji(emoji)}`, { query = options })
	end

	-- removes every reaction, or every reaction with `emoji`
	function channels.clearReactions(channelId: string, messageId: string, emoji: any?)
		if emoji then
			return rest:delete(`/channels/{channelId}/messages/{messageId}/reactions/{reactionEmoji(emoji)}`)
		end
		return rest:delete(`/channels/{channelId}/messages/{messageId}/reactions`)
	end

	function channels.typing(channelId: string)
		return rest:post(`/channels/{channelId}/typing`)
	end

	function channels.pins(channelId: string, options: { [string]: any }?)
		return rest:get(`/channels/{channelId}/messages/pins`, { query = options })
	end

	function channels.pin(channelId: string, messageId: string, reason: string?)
		return rest:put(`/channels/{channelId}/messages/pins/{messageId}`, nil, { reason = reason })
	end

	function channels.unpin(channelId: string, messageId: string, reason: string?)
		return rest:delete(`/channels/{channelId}/messages/pins/{messageId}`, { reason = reason })
	end

	-- allow/deny: permission names or masks; kind: "role" or "member"
	function channels.setPermission(channelId: string, targetId: string, kind: string, allow: any, deny: any, reason: string?)
		return rest:put(`/channels/{channelId}/permissions/{targetId}`, {
			type = if kind == "member" or kind == "1" then 1 else 0,
			allow = Permissions.toString(Permissions.resolve(allow)),
			deny = Permissions.toString(Permissions.resolve(deny)),
		}, { reason = reason })
	end

	function channels.deletePermission(channelId: string, targetId: string, reason: string?)
		return rest:delete(`/channels/{channelId}/permissions/{targetId}`, { reason = reason })
	end

	function channels.invites(channelId: string)
		return rest:get(`/channels/{channelId}/invites`)
	end

	-- options: max_age, max_uses, temporary, unique
	function channels.createInvite(channelId: string, options: { [string]: any }?, reason: string?)
		return rest:post(`/channels/{channelId}/invites`, json.object(options or {}), { reason = reason })
	end

	function channels.webhooks(channelId: string)
		return rest:get(`/channels/{channelId}/webhooks`)
	end

	function channels.createWebhook(channelId: string, name: string, avatar: string?, reason: string?)
		return rest:post(`/channels/{channelId}/webhooks`, { name = name, avatar = avatar }, { reason = reason })
	end

	-- a thread from a message; options: auto_archive_duration, rate_limit_per_user
	function channels.threadFromMessage(channelId: string, messageId: string, name: string, options: { [string]: any }?, reason: string?)
		local body = table.clone(options or {})
		body.name = name
		return rest:post(`/channels/{channelId}/messages/{messageId}/threads`, body, { reason = reason })
	end

	-- a thread without a message; options: type (11 public / 12 private), invitable, auto_archive_duration.
	-- In forum/media channels pass `message` (the first post) in options.
	function channels.createThread(channelId: string, name: string, options: { [string]: any }?, reason: string?)
		local body = table.clone(options or {})
		body.name = name
		if body.message then
			local m, files = messages.build(body.message, defaults())
			body.message = m
			return rest:post(`/channels/{channelId}/threads`, body, { reason = reason, files = files })
		end
		if body.type == nil then
			body.type = 11
		end
		return rest:post(`/channels/{channelId}/threads`, body, { reason = reason })
	end

	function channels.joinThread(threadId: string)
		return rest:put(`/channels/{threadId}/thread-members/@me`)
	end

	function channels.leaveThread(threadId: string)
		return rest:delete(`/channels/{threadId}/thread-members/@me`)
	end

	function channels.addThreadMember(threadId: string, userId: string)
		return rest:put(`/channels/{threadId}/thread-members/{userId}`)
	end

	function channels.removeThreadMember(threadId: string, userId: string)
		return rest:delete(`/channels/{threadId}/thread-members/{userId}`)
	end

	function channels.archivedThreads(channelId: string, private: boolean?, options: { [string]: any }?)
		return rest:get(`/channels/{channelId}/threads/archived/{if private then "private" else "public"}`, { query = options })
	end

	function channels.endPoll(channelId: string, messageId: string)
		return rest:post(`/channels/{channelId}/polls/{messageId}/expire`)
	end

	function channels.pollVoters(channelId: string, messageId: string, answerId: number, options: { [string]: any }?)
		return rest:get(`/channels/{channelId}/polls/{messageId}/answers/{answerId}`, { query = options })
	end

	-- guilds ---------------------------------------------------------------------------------

	local guilds = {}
	api.guilds = guilds

	function guilds.get(guildId: string, withCounts: boolean?)
		return rest:get(`/guilds/{guildId}`, { query = if withCounts then { with_counts = "true" } else nil })
	end

	function guilds.edit(guildId: string, fields: { [string]: any }, reason: string?)
		return rest:patch(`/guilds/{guildId}`, fields, { reason = reason })
	end

	function guilds.leave(guildId: string)
		return rest:delete(`/users/@me/guilds/{guildId}`)
	end

	function guilds.channels(guildId: string)
		return rest:get(`/guilds/{guildId}/channels`)
	end

	-- fields: name (required), type, topic, parent_id, permission_overwrites, ...
	function guilds.createChannel(guildId: string, fields: { [string]: any }, reason: string?)
		return rest:post(`/guilds/{guildId}/channels`, fields, { reason = reason })
	end

	function guilds.activeThreads(guildId: string)
		return rest:get(`/guilds/{guildId}/threads/active`)
	end

	function guilds.member(guildId: string, userId: string)
		return rest:get(`/guilds/{guildId}/members/{userId}`)
	end

	-- needs the GuildMembers intent; options: limit (1-1000), after
	function guilds.members(guildId: string, options: { [string]: any }?)
		return rest:get(`/guilds/{guildId}/members`, { query = options })
	end

	function guilds.searchMembers(guildId: string, search: string, limit: number?)
		return rest:get(`/guilds/{guildId}/members/search`, { query = { query = search, limit = limit or 10 } })
	end

	-- fields: nick, roles, mute, deaf, channel_id, communication_disabled_until, flags
	function guilds.editMember(guildId: string, userId: string, fields: { [string]: any }, reason: string?)
		return rest:patch(`/guilds/{guildId}/members/{userId}`, fields, { reason = reason })
	end

	function guilds.setNickname(guildId: string, nick: string?, reason: string?)
		return rest:patch(`/guilds/{guildId}/members/@me`, { nick = nick or json.null }, { reason = reason })
	end

	-- times a member out for `seconds` (max 28 days); 0 or nil removes the timeout
	function guilds.timeout(guildId: string, userId: string, seconds: number?, reason: string?)
		local untilValue: any = json.null
		if seconds and seconds > 0 then
			untilValue = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time() + math.floor(seconds))
		end
		return rest:patch(`/guilds/{guildId}/members/{userId}`, { communication_disabled_until = untilValue }, { reason = reason })
	end

	function guilds.kick(guildId: string, userId: string, reason: string?)
		return rest:delete(`/guilds/{guildId}/members/{userId}`, { reason = reason })
	end

	-- options: deleteMessageSeconds (0-604800), reason
	function guilds.ban(guildId: string, userId: string, options: { [string]: any }?)
		local opts = options or {} -- for some reason, luau language server doesnt accept `options = options or {}` here
		return rest:put(`/guilds/{guildId}/bans/{userId}`, json.object({
			delete_message_seconds = opts.deleteMessageSeconds,
		}), { reason = opts.reason })
	end

	function guilds.unban(guildId: string, userId: string, reason: string?)
		return rest:delete(`/guilds/{guildId}/bans/{userId}`, { reason = reason })
	end

	function guilds.bans(guildId: string, options: { [string]: any }?)
		return rest:get(`/guilds/{guildId}/bans`, { query = options })
	end

	function guilds.getBan(guildId: string, userId: string)
		return rest:get(`/guilds/{guildId}/bans/{userId}`)
	end

	function guilds.roles(guildId: string)
		return rest:get(`/guilds/{guildId}/roles`)
	end

	-- fields: name, permissions (names or mask), color, hoist, mentionable, icon, unicode_emoji
	function guilds.createRole(guildId: string, fields: { [string]: any }?, reason: string?)
		local body = table.clone(fields or {})
		if body.permissions ~= nil then
			body.permissions = Permissions.toString(Permissions.resolve(body.permissions))
		end
		if body.color ~= nil then
			body.color = ui.color(body.color)
		end
		return rest:post(`/guilds/{guildId}/roles`, json.object(body), { reason = reason })
	end

	function guilds.editRole(guildId: string, roleId: string, fields: { [string]: any }, reason: string?)
		local body = table.clone(fields)
		if body.permissions ~= nil then
			body.permissions = Permissions.toString(Permissions.resolve(body.permissions))
		end
		if body.color ~= nil then
			body.color = ui.color(body.color)
		end
		return rest:patch(`/guilds/{guildId}/roles/{roleId}`, json.object(body), { reason = reason })
	end

	function guilds.deleteRole(guildId: string, roleId: string, reason: string?)
		return rest:delete(`/guilds/{guildId}/roles/{roleId}`, { reason = reason })
	end

	function guilds.addRole(guildId: string, userId: string, roleId: string, reason: string?)
		return rest:put(`/guilds/{guildId}/members/{userId}/roles/{roleId}`, nil, { reason = reason })
	end

	function guilds.removeRole(guildId: string, userId: string, roleId: string, reason: string?)
		return rest:delete(`/guilds/{guildId}/members/{userId}/roles/{roleId}`, { reason = reason })
	end

	-- options: user_id, action_type, before, after, limit
	function guilds.auditLog(guildId: string, options: { [string]: any }?)
		return rest:get(`/guilds/{guildId}/audit-logs`, { query = options })
	end

	function guilds.invites(guildId: string)
		return rest:get(`/guilds/{guildId}/invites`)
	end

	function guilds.webhooks(guildId: string)
		return rest:get(`/guilds/{guildId}/webhooks`)
	end

	function guilds.emojis(guildId: string)
		return rest:get(`/guilds/{guildId}/emojis`)
	end

	-- image: a data URI ("data:image/png;base64,...")
	function guilds.createEmoji(guildId: string, name: string, image: string, roles: { string }?, reason: string?)
		return rest:post(`/guilds/{guildId}/emojis`, { name = name, image = image, roles = roles }, { reason = reason })
	end

	function guilds.deleteEmoji(guildId: string, emojiId: string, reason: string?)
		return rest:delete(`/guilds/{guildId}/emojis/{emojiId}`, { reason = reason })
	end

	function guilds.scheduledEvents(guildId: string)
		return rest:get(`/guilds/{guildId}/scheduled-events`, { query = { with_user_count = "true" } })
	end

	function guilds.autoModRules(guildId: string)
		return rest:get(`/guilds/{guildId}/auto-moderation/rules`)
	end

	-- users ----------------------------------------------------------------------------------

	local users = {}
	api.users = users

	function users.get(userId: string)
		return rest:get(`/users/{userId}`)
	end

	function users.me()
		return rest:get("/users/@me")
	end

	-- fields: username, avatar (data URI), banner
	function users.editMe(fields: { [string]: any })
		return rest:patch("/users/@me", fields)
	end

	function users.guilds(options: { [string]: any }?)
		return rest:get("/users/@me/guilds", { query = options })
	end

	local dmChannels: { [string]: string } = {}

	-- the DM channel with a user (cached)
	function users.dmChannel(userId: string)
		if dmChannels[userId] then
			return { id = dmChannels[userId], type = 1 }
		end
		local channel, err = rest:post("/users/@me/channels", { recipient_id = userId })
		if channel then
			dmChannels[userId] = channel.id
		end
		return channel, err
	end

	-- opens a DM and sends a message (fails if the user has DMs closed)
	function users.dm(userId: string, message: any)
		local channel, err = users.dmChannel(userId)
		if channel == nil then
			return nil, err
		end
		return channels.send(channel.id, message)
	end

	-- application commands -------------------------------------------------------------------

	local commands = {}
	api.commands = commands

	local function appId(): string
		local id = bot and bot.applicationId
		if id == nil then
			error("the application id isn't known yet (it is set on READY, or pass applicationId to Bot.new)", 3)
		end
		return id
	end

	local function scope(guildId: string?): string
		if guildId then
			return `/applications/{appId()}/guilds/{guildId}/commands`
		end
		return `/applications/{appId()}/commands`
	end

	function commands.list(guildId: string?)
		return rest:get(scope(guildId), { query = { with_localizations = "true" } })
	end

	function commands.get(commandId: string, guildId: string?)
		return rest:get(`{scope(guildId)}/{commandId}`)
	end

	function commands.create(command: { [string]: any }, guildId: string?)
		return rest:post(scope(guildId), command)
	end

	function commands.edit(commandId: string, command: { [string]: any }, guildId: string?)
		return rest:patch(`{scope(guildId)}/{commandId}`, command)
	end

	function commands.delete(commandId: string, guildId: string?)
		return rest:delete(`{scope(guildId)}/{commandId}`)
	end

	-- replaces every command in the scope with `list`
	function commands.set(list: { any }, guildId: string?)
		return rest:put(scope(guildId), json.array(list))
	end

	function commands.permissions(guildId: string, commandId: string?)
		if commandId then
			return rest:get(`/applications/{appId()}/guilds/{guildId}/commands/{commandId}/permissions`)
		end
		return rest:get(`/applications/{appId()}/guilds/{guildId}/commands/permissions`)
	end

	-- interactions ---------------------------------------------------------------------------

	local interactions = {}
	api.interactions = interactions

	-- the initial response; `withResponse` asks Discord to return the created message
	function interactions.callback(id: string, token: string, body: any, files: { any }?, withResponse: boolean?)
		return rest:request("POST", `/interactions/{id}/{token}/callback`, {
			body = body,
			files = files,
			auth = false,
			query = if withResponse then { with_response = "true" } else nil,
		})
	end

	function interactions.getOriginal(token: string)
		return rest:request("GET", `/webhooks/{appId()}/{token}/messages/@original`, { auth = false })
	end

	function interactions.editOriginal(token: string, message: any)
		local body, files = messages.build(message, defaults(), true)
		return rest:request("PATCH", `/webhooks/{appId()}/{token}/messages/@original`, { body = body, files = files, auth = false })
	end

	function interactions.deleteOriginal(token: string)
		return rest:request("DELETE", `/webhooks/{appId()}/{token}/messages/@original`, { auth = false })
	end

	function interactions.followUp(token: string, message: any, ephemeral: boolean?)
		local d = defaults() or {}
		d.ephemeral = ephemeral
		local body, files = messages.build(message, d)
		return rest:request("POST", `/webhooks/{appId()}/{token}`, { body = body, files = files, auth = false })
	end

	function interactions.editFollowUp(token: string, messageId: string, message: any)
		local body, files = messages.build(message, defaults(), true)
		return rest:request("PATCH", `/webhooks/{appId()}/{token}/messages/{messageId}`, { body = body, files = files, auth = false })
	end

	function interactions.deleteFollowUp(token: string, messageId: string)
		return rest:request("DELETE", `/webhooks/{appId()}/{token}/messages/{messageId}`, { auth = false })
	end

	-- webhooks -------------------------------------------------------------------------------

	local webhooks = {}
	api.webhooks = webhooks

	function webhooks.get(webhookId: string, token: string?)
		if token then
			return rest:request("GET", `/webhooks/{webhookId}/{token}`, { auth = false })
		end
		return rest:get(`/webhooks/{webhookId}`)
	end

	function webhooks.edit(webhookId: string, fields: { [string]: any }, reason: string?)
		return rest:patch(`/webhooks/{webhookId}`, fields, { reason = reason })
	end

	function webhooks.delete(webhookId: string, reason: string?)
		return rest:delete(`/webhooks/{webhookId}`, { reason = reason })
	end

	-- message also takes `username`, `avatarUrl`, `threadId`, `threadName`; `wait` returns the message
	function webhooks.execute(webhookId: string, token: string, message: any, wait: boolean?)
		local body, files = messages.build(message, defaults())
		if type(message) == "table" then
			body.username = message.username
			body.avatar_url = message.avatarUrl
			body.thread_name = message.threadName
		end
		local query: { [string]: any } = { wait = if wait == false then "false" else "true" }
		if type(message) == "table" and message.threadId then
			query.thread_id = message.threadId
		end
		-- components (including v2) on webhooks owned by an app
		if body.components then
			query.with_components = "true"
		end
		return rest:request("POST", `/webhooks/{webhookId}/{token}`, { body = body, files = files, auth = false, query = query })
	end

	-- "https://discord.com/api/webhooks/<id>/<token>" -> id, token
	function webhooks.parseUrl(url: string): (string?, string?)
		return string.match(url, "/webhooks/(%d+)/([%w_%-]+)")
	end

	-- the application ------------------------------------------------------------------------

	local application = {}
	api.application = application

	function application.me()
		return rest:get("/applications/@me")
	end

	-- fields: description, interactions_endpoint_url, install_params, integration_types_config, ...
	function application.edit(fields: { [string]: any })
		return rest:patch("/applications/@me", fields)
	end

	-- emojis uploaded to the application (usable everywhere by the bot)
	function application.emojis()
		return rest:get(`/applications/{appId()}/emojis`)
	end

	function application.createEmoji(name: string, image: string)
		return rest:post(`/applications/{appId()}/emojis`, { name = name, image = image })
	end

	function application.deleteEmoji(emojiId: string)
		return rest:delete(`/applications/{appId()}/emojis/{emojiId}`)
	end

	-- monetization: options: user_id, guild_id, sku_ids, exclude_ended
	function application.entitlements(options: { [string]: any }?)
		return rest:get(`/applications/{appId()}/entitlements`, { query = options })
	end

	function application.consumeEntitlement(entitlementId: string)
		return rest:post(`/applications/{appId()}/entitlements/{entitlementId}/consume`)
	end

	function application.skus()
		return rest:get(`/applications/{appId()}/skus`)
	end

	-- misc -----------------------------------------------------------------------------------

	api.stickers = {
		get = function(stickerId: string)
			return rest:get(`/stickers/{stickerId}`)
		end,
		guild = function(guildId: string)
			return rest:get(`/guilds/{guildId}/stickers`)
		end,
	}

	api.invites = {
		get = function(code: string)
			return rest:get(`/invites/{code}`, { query = { with_counts = "true" } })
		end,
		delete = function(code: string, reason: string?)
			return rest:delete(`/invites/{code}`, { reason = reason })
		end,
	}

	api.gateway = function()
		return rest:get("/gateway/bot")
	end

	-- raw access for endpoints without a wrapper: api.request("GET", "/route", { query = ... })
	function api.request(method: string, route: string, options: any?)
		return rest:request(method, route, options)
	end

	return api
end
