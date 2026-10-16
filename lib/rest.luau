--[[
	REST client for the Discord HTTP API, with rate limit handling

	    local rest = Rest.new(token)
	    local message, err = rest:request("POST", "/channels/123/messages", { body = { content = "hi" } })

	Failures don't raise: calls return `nil, err`, where `err` is a table
	`{ status, code, message, errors, method, route }` that prints nicely with tostring.
]]

local httpx = require("@httpx")
local json = require("@sonata/json")
local task = require("@sonata/task")
local datetime = require("@sonata/datetime")
local stripNull = require("./json").stripNull

local API = "https://discord.com/api/v10"
local USER_AGENT = "DiscordBot (https://github.com/loopy5418/discord, 0.1.0)"
local MAX_RETRIES = 4

export type File = {
	name: string, -- file name Discord shows ("image.png"); refer to it as attachment://image.png
	data: string?, -- the contents
	path: string?, -- or a file on disk to read
	contentType: string?,
	description: string?, -- alt text
	spoiler: boolean?, -- prefixes the name with SPOILER_
}

export type RequestOptions = {
	body: any?, -- encoded as JSON
	query: { [string]: any }?,
	files: { File }?, -- sends multipart/form-data with the body as payload_json
	reason: string?, -- X-Audit-Log-Reason
	auth: boolean?, -- false sends no Authorization header (interaction webhooks)
	headers: { [string]: string }?,
}

local DiscordError = {}
DiscordError.__index = DiscordError
DiscordError.__tostring = function(self)
	local text = `{self.method} {self.route}: {self.status or "?"}`
	if self.code then
		text ..= ` (code {self.code})`
	end
	if self.message then
		text ..= ` {self.message}`
	end
	if self.errors then
		text ..= " " .. json.encode(self.errors)
	end
	return text
end

local function newError(fields: { [string]: any })
	return setmetatable(fields, DiscordError)
end

-- percent-encodes everything but unreserved characters (RFC 3986)
local function encodeComponent(s: string): string
	return (string.gsub(s, "[^%w%-%._~]", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

-- the rate limit bucket a route belongs to: ids are folded together except the "major
-- parameters" (channel, guild, webhook/interaction ids), which get buckets of their own
-- https://docs.discord.com/developers/topics/rate-limits
local function bucketKey(method: string, route: string): string
	local key = string.gsub(route, "%?.*$", "")
	key = string.gsub(key, "/%d%d%d%d%d+", "/:id")
	-- the major ids keep their own bucket
	local major = string.match(route, "^/channels/(%d+)") or string.match(route, "^/guilds/(%d+)")
		or string.match(route, "^/webhooks/(%d+/[^/]+)") or string.match(route, "^/interactions/(%d+/[^/]+)")
	-- reactions share one bucket per channel regardless of the emoji
	key = string.gsub(key, "/reactions/.*$", "/reactions")
	return `{method} {key} {major or ""}`
end

local Rest = {}
Rest.__index = Rest

function Rest.new(token: string, options: { debug: boolean?, timeout: number? }?)
	options = options or {}
	local self = setmetatable({
		token = string.gsub(token, "^Bot%s+", ""),
		debug = options and options.debug == true,
		client = httpx.client({
			timeout = options and options.timeout or 30,
			userAgent = USER_AGENT,
			cookies = false,
		}),
		_buckets = {} :: { [string]: any },
		_globalUntil = 0,
	}, Rest)
	return self
end

Rest.encodeComponent = encodeComponent
Rest.API = API

function Rest:_bucket(key: string)
	local bucket = self._buckets[key]
	if bucket == nil then
		bucket = { remaining = 1, resetAt = 0, lock = task.mutex() }
		self._buckets[key] = bucket
	end
	return bucket
end

local function readFile(file: File): string
	if file.data then
		return file.data
	end
	if file.path then
		local fs = require("@sonata/fs")
		return fs.readFile(file.path)
	end
	error(`file "{file.name}" needs data or path`, 3)
end

-- builds the multipart body for `files` (with the JSON body as payload_json)
-- https://docs.discord.com/developers/reference#uploading-files
local function multipartFor(body: any, files: { File })
	body = body or {}
	local attachments = {}
	-- keep attachments the caller listed (e.g. existing ones when editing)
	for _, a in body.attachments or {} do
		table.insert(attachments, a)
	end
	local parts = {}
	for i, file in files do
		local name = file.name
		if file.spoiler and string.sub(name, 1, 8) ~= "SPOILER_" then
			name = "SPOILER_" .. name
		end
		table.insert(attachments, { id = i - 1, filename = name, description = file.description })
		table.insert(parts, {
			name = `files[{i - 1}]`,
			filename = name,
			value = readFile(file),
			contentType = file.contentType or "application/octet-stream",
		})
	end
	body.attachments = attachments
	table.insert(parts, 1, { name = "payload_json", value = json.encode(body), contentType = "application/json" })
	return parts
end

--[[
	Sends a request. `route` is the path after /api/v10, e.g. "/channels/123/messages".
	Returns the decoded JSON (or `true` for empty responses), or `nil, err`.
]]
function Rest:request(method: string, route: string, options: RequestOptions?): (any, any)
	local optionsTF = options or {}
	method = string.upper(method)
	local key = bucketKey(method, route)
	local bucket = self:_bucket(key)

	local headers = {}
	if optionsTF.auth ~= false then
		headers["Authorization"] = "Bot " .. self.token
	end
	if optionsTF.reason then
		headers["X-Audit-Log-Reason"] = encodeComponent(optionsTF.reason)
	end
	for k, v in optionsTF.headers or {} do
		headers[k] = v
	end

	local requestOptions: { [string]: any } = { headers = headers, query = optionsTF.query }
	if optionsTF.files and #optionsTF.files > 0 then
		requestOptions.multipart = multipartFor(optionsTF.body, optionsTF.files)
	elseif optionsTF.body ~= nil then
		requestOptions.json = optionsTF.body
	end

	bucket.lock:lock()
	local result, err
	local attempt = 0
	while true do
		attempt += 1
		-- wait out the global limit and this bucket's limit
		local now = datetime.monotonic()
		if self._globalUntil > now then
			task.wait(self._globalUntil - now)
		end
		now = datetime.monotonic()
		if bucket.remaining <= 0 and bucket.resetAt > now then
			if self.debug then
				print(`[rest] {key}: waiting {bucket.resetAt - now}s for the rate limit`)
			end
			task.wait(bucket.resetAt - now)
		end

		if self.debug then
			print("[rest]", method, route)
		end
		local res, netErr = self.client:request(method, API .. route, requestOptions)
		if res == nil then
			if attempt < MAX_RETRIES then
				task.wait(attempt)
				continue
			end
			result, err = nil, newError({ method = method, route = route, message = tostring(netErr) })
			break
		end

		local remaining = tonumber(res.headers["x-ratelimit-remaining"])
		local resetAfter = tonumber(res.headers["x-ratelimit-reset-after"])
		if remaining ~= nil and resetAfter ~= nil then
			bucket.remaining = remaining
			bucket.resetAt = datetime.monotonic() + resetAfter
		end

		if res.status == 429 then
			local data = stripNull(res:json()) or {}
			local retryAfter = tonumber(data.retry_after) or tonumber(res.headers["retry-after"]) or 1
			if data.global or res.headers["x-ratelimit-global"] then
				self._globalUntil = datetime.monotonic() + retryAfter
			else
				bucket.remaining = 0
				bucket.resetAt = datetime.monotonic() + retryAfter
			end
			print(`[rest] rate limited on {method} {route}, retrying in {retryAfter}s`)
			if attempt < MAX_RETRIES then
				continue
			end
		elseif res.status >= 500 and attempt < MAX_RETRIES then
			task.wait(attempt)
			continue
		end

		if res.ok then
			if res.status == 204 or res.body == nil or res.body == "" then
				result = true
			else
				result = stripNull(res:json())
				if result == nil then
					result = true
				end
			end
		else
			local data = stripNull(res:json())
			local fields = { method = method, route = route, status = res.status }
			if type(data) == "table" then
				fields.code = data.code
				fields.message = data.message
				fields.errors = data.errors
			else
				fields.message = res.body
			end
			err = newError(fields)
		end
		break
	end
	bucket.lock:unlock()
	return result, err
end

function Rest:get(route: string, options: RequestOptions?)
	return self:request("GET", route, options)
end

function Rest:post(route: string, body: any?, options: RequestOptions?)
	local o = options or {}
	o.body = body
	return self:request("POST", route, o)
end

function Rest:patch(route: string, body: any?, options: RequestOptions?)
	local o = options or {}
	o.body = body
	return self:request("PATCH", route, o)
end

function Rest:put(route: string, body: any?, options: RequestOptions?)
	local o = options or {}
	o.body = body
	return self:request("PUT", route, o)
end

function Rest:delete(route: string, options: RequestOptions?)
	return self:request("DELETE", route, options)
end

Rest.isError = function(value: any): boolean
	return getmetatable(value) == DiscordError
end

return Rest
