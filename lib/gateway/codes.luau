--[[
    Codes list
]]

local codes = {}

-- opcodes
-- https://docs.discord.com/developers/topics/opcodes-and-status-codes#gateway
codes.OP = {
	DISPATCH = 0,
	HEARTBEAT = 1,
	IDENTIFY = 2,
	PRESENCE_UPDATE = 3,
	VOICE_STATE_UPDATE = 4,
	RESUME = 6,
	RECONNECT = 7,
	REQUEST_GUILD_MEMBERS = 8,
	INVALID_SESSION = 9,
	HELLO = 10,
	HEARTBEAT_ACK = 11,
}

-- close codes
-- https://docs.discord.com/developers/topics/opcodes-and-status-codes#gateway
codes.FATAL_CLOSE = {
	[4004] = "authentication failed (bad token)",
	[4010] = "invalid shard",
	[4011] = "sharding required",
	[4012] = "invalid API version",
	[4013] = "invalid intents",
	[4014] = "disallowed intents (enable privileged intents in the developer portal)",
}

-- close codes where discord doesn't want you to reconnect
-- fresh identity is fine
-- https://docs.discord.com/developers/topics/opcodes-and-status-codes#gateway
codes.NO_RESUME_CLOSE = {
	[4007] = true, -- invalid seq
	[4009] = true, -- session timed out
}

-- closing with 100* tells discord that we gracefully shut down
-- the connection, which we don't want when we want to resume
-- use this for resuming
codes.RESUME_CLOSE = 4000

return codes