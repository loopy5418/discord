--[[
	Gateway client

	    local gateway = require("@discord/lib/gateway/gateway")
	    local bot = gateway.new({ token = TOKEN, intents = { "Guilds", "GuildMessages" } })
	    bot:on("READY", function(d) print("logged in as", d.user.username) end)
	    bot:run() -- blocks until bot:stop() or a fatal close code
]]

local httpx = require("@httpx")
local json = require("@sonata/json")
local task = require("@sonata/task")
local crypto = require("@sonata/crypto")
local datetime = require("@sonata/datetime")

local codes = require("./codes")
local decodeJson = require("../json").decode
local Intent = require("./intents")

local API = "https://discord.com/api/v10"
local QUERY = "?v=10&encoding=json"

export type Options = {
	token: string, -- the raw bot token (with or without a "Bot " prefix)
	intents: Intent.IntentInput?, -- names, flags, or a mask (default Intent.Default)
	presence: { [string]: any }?, -- initial presence sent with identify
	debug: boolean?, -- print every payload
}

local Gateway = {}
Gateway.__index = Gateway -- for oop

local function new(options: Options)
	local token = string.gsub(options.token, "^Bot%s+", "")
	return setmetatable({
		token = token,
		intents = Intent.resolve(options.intents),
		presence = options.presence,
		debug = options.debug == true,

		-- keep session state for resuming
		sessionId = nil :: string?,
		resumeUrl = nil :: string?,
		seq = nil :: number?,
		user = nil :: any,
		latency = nil :: number?, -- seconds between the last heartbeat and its ACK
		_beatSentAt = nil :: number?,

		ws = nil :: any,
		running = false,
		_handlers = {} :: { [string]: { (...any) -> () } },
		_conn = nil :: any,
	}, Gateway)
end

local function log(...)
	print("[gateway]", ...)
end

-- registers a handler for a dispatch event ("READY", "MESSAGE_CREATE", ...), or "*" for every
-- event (called with name, data). handlers run in their own task, so they may yield
function Gateway:on(event: string, handler: (...any) -> ())
	local list = self._handlers[event]
	if list == nil then
		list = {}
		self._handlers[event] = list
	end
	table.insert(list, handler)

	-- warn about handlers that will never fire with the intents we identify with
	local receives, needed = Intent.receives(self.intents, event)
	if not receives and needed then
		log(`warning: "{event}" needs one of these intents, which the bot doesn't have: {table.concat(needed, ", ")}`)
	elseif (event == "MESSAGE_CREATE" or event == "MESSAGE_UPDATE") and not Intent.has(self.intents, "MessageContent") then
		log(`note: without the MessageContent intent, "{event}" has empty content except in DMs and mentions`)
	end
	return self
end

function Gateway:_emit(event: string, ...: any)
	local list = self._handlers[event]
	if list then
		for _, handler in list do
			task.spawn(handler, ...)
		end
	end
end

-- send raw gateway payload
function Gateway:send(op: number, d: any): (boolean, string?)
	local ws = self.ws
	if ws == nil or ws.closed then
		return false, "not connected"
	end
	if self.debug then
		local shown = json.encode(d)
		if op == codes.OP.IDENTIFY or op == codes.OP.RESUME then
			shown = string.gsub(shown, '"token":"[^"]*"', '"token":"<redacted>"')
		end
		log("->", op, shown)
	end
	return ws:sendJson({ op = op, d = if d == nil then json.null else d })
end

-- update the bots presence and/or status
-- bot:setPresence({ status = "online", activities = { { name = "you", type = 3 } } }).
function Gateway:setPresence(presence: { [string]: any })
	presence.since = presence.since or json.null
	presence.activities = presence.activities or {}
	presence.status = presence.status or "online"
	presence.afk = presence.afk or false
	return self:send(codes.OP.PRESENCE_UPDATE, presence)
end

function Gateway:_identify()
	log("identifying")
	self:send(codes.OP.IDENTIFY, {
		token = self.token,
		intents = self.intents,
		properties = {
			os = "linux",
			browser = "sonata",
			device = "sonata",
		},
		presence = self.presence,
	})
end

function Gateway:_resume()
	log("resuming session", self.sessionId, "at seq", self.seq)
	self:send(codes.OP.RESUME, {
		token = self.token,
		session_id = self.sessionId,
		seq = self.seq or json.null,
	})
end

function Gateway:_heartbeat()
	self._beatSentAt = datetime.monotonic()
	self:send(codes.OP.HEARTBEAT, self.seq or json.null)
end

-- asks for guild members; they arrive as GUILD_MEMBERS_CHUNK events.
-- options: query (name prefix, "" for all), limit, user_ids, presences, nonce
-- (listing everyone needs the GuildMembers intent)
function Gateway:requestGuildMembers(guildId: string, options: { [string]: any }?)
	local d: { [string]: any } = { guild_id = guildId, limit = 0 }
	for k, v in options or {} do
		d[k] = v
	end
	if d.user_ids == nil and d.query == nil then
		d.query = ""
	end
	return self:send(codes.OP.REQUEST_GUILD_MEMBERS, d)
end

-- heartbeat loop for one connection, "conn" is that connection's state
function Gateway:_startHeartbeat(conn, intervalMs: number)
	local interval = intervalMs / 1000
	conn.heartbeat = task.spawn(function()
		-- Discord asks for the first beat after interval * jitter, jitter in [0, 1).
		task.wait(interval * crypto.randomInt(0, 999) / 1000)
		while not conn.ws.closed do
			if not conn.acked then
				log("no heartbeat ACK, connection is a zombie; reconnecting")
				conn.resume = true
				conn.ws:close(codes.RESUME_CLOSE, "zombie connection")
				return
			end
			conn.acked = false
			self:_heartbeat()
			task.wait(interval)
		end
	end)
end

function Gateway:_handle(conn, payload)
	local op, d, s, t = payload.op, payload.d, payload.s, payload.t
	if type(s) == "number" then
		self.seq = s
	end

	if op == codes.OP.HELLO then
		conn.acked = true
		self:_startHeartbeat(conn, d.heartbeat_interval)
		if self.sessionId and conn.tryResume then
			self:_resume()
		else
			self:_identify()
		end
	elseif op == codes.OP.HEARTBEAT_ACK then
		conn.acked = true
		if self._beatSentAt then
			self.latency = datetime.monotonic() - self._beatSentAt
		end
	elseif op == codes.OP.HEARTBEAT then
		-- discord wants a beat right now
		self:_heartbeat()
	elseif op == codes.OP.RECONNECT then
		log("server asked us to reconnect")
		conn.resume = true
		conn.ws:close(codes.RESUME_CLOSE, "reconnect requested")
	elseif op == codes.OP.INVALID_SESSION then
		-- d is true when the session can still be resumed
		log("invalid session (resumable: " .. tostring(d) .. ")")
		if d ~= true then
			self.sessionId = nil
			self.resumeUrl = nil
			self.seq = nil
		end
		conn.resume = d == true
		-- discord asks for a random 1-5 second wait before identifying again
		conn.delay = crypto.randomInt(1000, 5000) / 1000
		conn.ws:close(codes.RESUME_CLOSE, "invalid session")
	elseif op == codes.OP.DISPATCH then
		if t == "READY" then
			self.sessionId = d.session_id
			self.resumeUrl = d.resume_gateway_url
			self.user = d.user
			log(`ready as {d.user.username} ({d.user.id}), in {#d.guilds} guild(s)`)
		elseif t == "RESUMED" then
			log("resumed")
		end
		self:_emit(t, d)
		self:_emit("*", t, d)
	end
end

-- runs one connection until it closes and returns how the loop should continue:
-- "resume", "identify", or "fatal" (with a reason)
function Gateway:_connectOnce(url: string, tryResume: boolean): (string, string?)
	log("connecting to", url)
	local ws, err = httpx.websocket.connect(url .. QUERY, { maxMessageSize = 64 * 1024 * 1024 })
	if ws == nil then
		log("connect failed:", err)
		return if tryResume then "resume" else "identify", nil
	end
	self.ws = ws

	local conn = {
		ws = ws,
		acked = true,
		tryResume = tryResume,
		resume = nil :: boolean?, -- set when we close the socket ourselves
		delay = nil :: number?,
		heartbeat = nil :: thread?,
	}
	self._conn = conn

	for message, kind in ws:messages() do
		if kind == "text" then
			local ok, payload = pcall(decodeJson, message)
			if ok and type(payload) == "table" then
				if self.debug then
					log("<-", payload.op, if type(payload.t) == "string" then payload.t else "", message)
				end
				self:_handle(conn, payload)
			else
				log("bad payload:", payload)
			end
		end
	end

	if conn.heartbeat then
		pcall(task.cancel, conn.heartbeat)
	end
	self.ws = nil
	self._conn = nil

	local code = ws.closeCode
	log("closed:", code, ws.closeReason)

	if not self.running then
		return "stopped", nil
	end
	if code and codes.FATAL_CLOSE[code] then
		local reason = `{code}: {codes.FATAL_CLOSE[code]}`
		if code == 4014 then
			local names = Intent.privilegedIn(self.intents)
			if #names > 0 then
				reason ..= ` ({table.concat(names, ", ")})`
			end
		end
		return "fatal", reason
	end
	if conn.delay then
		task.wait(conn.delay)
	end
	if conn.resume ~= nil then
		return if conn.resume then "resume" else "identify", nil
	end
	if code and codes.NO_RESUME_CLOSE[code] then
		return "identify", nil
	end
	return "resume", nil
end

local function fetchGatewayUrl(token: string): (string?, string?, number?)
	local res, err = httpx.get(API .. "/gateway/bot", {
		headers = { Authorization = "Bot " .. token },
	})
	if res == nil then
		return nil, err
	end
	if not res.ok then
		return nil, `GET /gateway/bot: {res.status} {res.body}`, res.status
	end
	local data = res:json()
	if data == nil or data.url == nil then
		return nil, "GET /gateway/bot: no url in response"
	end
	return data.url, nil
end

-- connects and keeps the bot online, blocks until bot:stop() is called or Discord closes
-- with a fatal code; returns "false, reason" in that case.
function Gateway:run(): (boolean, string?)
	self.running = true
	log("intents:", table.concat(Intent.names(self.intents), ", "))
	local baseUrl = nil
	local failures = 0
	local mode = "identify"

	while self.running do
		local url
		if mode == "resume" and self.sessionId and self.resumeUrl then
			url = self.resumeUrl
		else
			mode = "identify"
			if baseUrl == nil then
				local err, status
				baseUrl, err, status = fetchGatewayUrl(self.token)
				if baseUrl == nil then
					log("could not get the gateway url:", err)
					if status == 401 then
						self.running = false
						return false, codes.FATAL_CLOSE[4004]
					end
				end
			end
			url = baseUrl
		end

		local reason
		if url then
			local started = os.time()
			mode, reason = self:_connectOnce(url, mode == "resume")
			-- A connection that lived a while resets the backoff.
			if os.time() - started > 60 then
				failures = 0
			end
		end

		if mode == "fatal" then
			log("fatal:", reason)
			self.running = false
			return false, reason
		elseif mode == "stopped" then
			break
		end

		failures += 1
		if failures > 1 then
			local backoff = math.min(2 ^ (failures - 1), 60)
			log(`reconnecting in {backoff}s`)
			task.wait(backoff)
		end
	end
	return true, nil
end

-- Disconnects for good (the session is dropped).
function Gateway:stop()
	self.running = false
	if self.ws and not self.ws.closed then
		self.ws:close(1000, "shutting down")
	end
end

return {
	new = new,
	intents = Intent,
}