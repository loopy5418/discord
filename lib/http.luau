--[[
	HTTP interactions endpoint (an alternative to receiving interactions over the gateway)

	Set the endpoint in the developer portal (General Information > Interactions Endpoint URL),
	then:

	    bot:listen({ port = 8080, publicKey = "<the application's public key>" })

	Requests are verified with the ed25519 signature Discord sends; the first response of each
	interaction goes back in the HTTP response.
]]

local httpx = require("@httpx")
local json = require("@sonata/json")
local task = require("@sonata/task")
local crypto = require("@sonata/crypto")

local function hexDecode(hex: string): string?
	if #hex % 2 ~= 0 or string.find(hex, "[^%x]") then
		return nil
	end
	return (string.gsub(hex, "%x%x", function(byte)
		return string.char(tonumber(byte, 16) :: number)
	end))
end

export type ListenOptions = {
	publicKey: string, -- hex, from the developer portal
	port: number?, -- default 8080
	host: string?,
	path: string?, -- default "/interactions"
	responseTimeout: number?, -- seconds to wait for the first response (default 2.8)
}

return function(bot: any, options: ListenOptions)
	local key = hexDecode(options.publicKey or "")
	if key == nil then
		error("listen: publicKey must be the application's public key in hex", 2)
	end
	local timeout = options.responseTimeout or 2.8

	local app = httpx.app()
	app:post(options.path or "/interactions", function(req)
		local signature = req.headers["x-signature-ed25519"]
		local timestamp = req.headers["x-signature-timestamp"]
		local body = req.body or ""
		local sig = signature and hexDecode(signature)
		if sig == nil or timestamp == nil or not crypto.verify(key, timestamp .. body, sig) then
			return 401, "invalid request signature"
		end

		local ok, interaction = pcall(json.decode, body)
		if not ok or type(interaction) ~= "table" then
			return 400, "bad json"
		end
		if interaction.type == 1 then
			return { type = 1 } -- PING -> PONG
		end

		local ch = task.channel()
		local transport = { open = true }
		function transport.respond(response: any): boolean
			if not transport.open then
				return false
			end
			transport.open = false
			ch:trySend(response)
			return true
		end

		task.spawn(function()
			bot:_handleInteraction(interaction, transport)
		end)

		local got, response = ch:recv(timeout)
		transport.open = false
		if got then
			return response
		end
		-- nothing answered in time; Discord shows "interaction failed"
		return 500, "no response"
	end)

	local srv, err = app:listen({ port = options.port or 8080, host = options.host })
	if srv == nil then
		error(`listen: {err}`, 2)
	end
	print(`[http] interactions endpoint on {srv.url}{options.path or "/interactions"}`)
	return srv
end
