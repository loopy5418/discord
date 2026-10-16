--[[
	Connection check: validates the token over REST, shows the application's settings, then
	connects to the gateway, waits for READY and disconnects.

	    sn run -- whoami --token <token>
]]

local process = require("@sonata/process")
local datetime = require("@sonata/datetime")
local task = require("@sonata/task")
local discord = require("../../lib") -- in your project: require("@discord")
local config = require("../_config")

local cfg = config.require()
local api = discord.makeApi(discord.Rest.new(cfg.token, { debug = cfg.debugRest }))

local function ok(text: string)
	print("  ✓ " .. text)
end
local function warn(text: string)
	print("  ! " .. text)
end
local function fail(text: string)
	print("  ✗ " .. text)
	process.exit(1)
end

print("REST")
local started = datetime.monotonic()
local me, err = api.users.me()
if me == nil then
	if err and err.status then
		fail(`the token was rejected: {tostring(err)}`)
	end
	fail(`couldn't reach Discord: {tostring(err)}`)
end
ok(`logged in as {me.username} ({me.id}) in {math.floor((datetime.monotonic() - started) * 1000)}ms`)

local app = api.application.me()
if app then
	ok(`application "{app.name}"{if app.bot_public then ", public" else ", private"}, about {app.approximate_guild_count or 0} server(s)`)
	local owner = if app.team then `team {app.team.name}` elseif app.owner then app.owner.username else "?"
	ok(`owned by {owner}`)
	local flags = app.flags or 0
	local function has(...: number): boolean
		for _, bit in { ... } do
			if math.floor(flags / 2 ^ bit) % 2 == 1 then
				return true
			end
		end
		return false
	end
	local privileged = {
		{ "MessageContent", has(18, 19), "prefix commands outside DMs and mentions" },
		{ "GuildMembers", has(14, 15), "member events and member lists" },
		{ "GuildPresences", has(12, 13), "presence updates" },
	}
	for _, p in privileged do
		if p[2] then
			ok(`{p[1]} intent enabled`)
		else
			warn(`{p[1]} intent not enabled (needed for {p[3]})`)
		end
	end
	if app.interactions_endpoint_url and app.interactions_endpoint_url ~= "" then
		warn(`interactions go to {app.interactions_endpoint_url}, not the gateway`)
	end
	print(`\ninvite: https://discord.com/oauth2/authorize?client_id={app.id}&scope=bot+applications.commands&permissions={discord.permissions.toString(discord.permissions.resolve({ "ViewChannel", "SendMessages", "EmbedLinks", "AttachFiles", "ReadMessageHistory", "AddReactions", "UseExternalEmojis" }))}`)
	print(`install for yourself: https://discord.com/oauth2/authorize?client_id={app.id}&integration_type=1&scope=applications.commands\n`)
else
	warn("couldn't fetch the application")
end

local gw = api.gateway()
print("Gateway")
if gw and gw.url then
	local limit = gw.session_start_limit or {}
	ok(`{gw.url}, {gw.shards} shard(s) recommended`)
	ok(`{limit.remaining or "?"}/{limit.total or "?"} session starts left (resets in {math.floor((limit.reset_after or 0) / 1000)}s)`)
else
	fail("couldn't fetch the gateway url")
end

-- connect without privileged intents so this works on any application
local bot = discord.new({ token = cfg.token, intents = { "Guilds" }, syncCommands = false, debug = cfg.debug })
local connectStarted = datetime.monotonic()
bot:once("READY", function(_, data)
	ok(`READY in {math.floor((datetime.monotonic() - connectStarted) * 1000)}ms, session {data.session_id}, {#data.guilds} server(s)`)
	task.wait(0.5)
	bot:stop()
end)
task.delay(30, function()
	print("  ✗ no READY within 30s")
	process.exit(1)
end)
local connected, reason = bot:run()
if not connected then
	fail(`gateway closed the connection: {reason}`)
end
print("\nall good")
process.exit(0)
