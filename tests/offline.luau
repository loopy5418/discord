--[[
	Offline tests

	    sn run --entry tests/offline.luau
]]

local json = require("@sonata/json")
local task = require("@sonata/task")
local crypto = require("@sonata/crypto")
local Bot = require("../lib")
local commands = require("../lib/commands")
local Permissions = require("../lib/permissions")
local ui = Bot.ui

local passed, failed = 0, 0
local function check(name: string, cond: any, detail: any?)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL", name, if detail ~= nil then json.encode(detail) else "")
	end
end

-- a bot with a fake REST client ---------------------------------------------------------------

local bot = Bot.new({ token = "fake", prefix = "!", syncCommands = false, commandCache = false, owners = { "1" }, autoDefer = false })
bot.applicationId = "999"
bot.user = { id = "999", username = "testbot" }

local calls = {}
local responses: { [string]: any } = {}
bot.rest.request = function(_, method, route, options)
	table.insert(calls, { method = method, route = route, body = options and options.body, files = options and options.files, query = options and options.query })
	for pattern, response in responses do
		if string.match(method .. " " .. route, pattern) then
			if type(response) == "function" then
				return response(method, route, options)
			end
			return response
		end
	end
	if string.find(route, "/callback$") then
		return { resource = { message = { id = "reply1", channel_id = "c1", components = options.body.data and options.body.data.components } } }
	end
	if method == "POST" and string.find(route, "/messages$") then
		return { id = "sent" .. #calls, channel_id = "c1" }
	end
	return true
end

local function last()
	return calls[#calls]
end

local function reset()
	table.clear(calls)
end

bot:load("../examples/showcase/commands", "../examples/showcase/components", "../examples/showcase/events")
check("loaded commands", #bot.commandList >= 10, #bot.commandList)

-- registration JSON ---------------------------------------------------------------------------

local payloads = {}
for _, def in bot.commandList do
	local body = commands.toJSON(def)
	if body then
		payloads[body.name .. ":" .. body.type] = body
	end
end
check("ping json", payloads["ping:1"] and payloads["ping:1"].description == "Check that the bot is alive")
check("purge is prefix-only", payloads["purge:1"] == nil)
check("user command", payloads["User Info:2"] and payloads["User Info:2"].integration_types[2] == 1)
check("message command contexts", payloads["Quote:3"] and #payloads["Quote:3"].contexts == 3)
local cfg = payloads["config:1"]
check("config group", cfg and cfg.options[2].type == 2 and cfg.options[2].options[1].name == "set", cfg)
check("ban permissions", payloads["ban:1"].default_member_permissions == "4")
check("color autocomplete flag", payloads["color:1"].options[1].autocomplete == true)
check("encodes", pcall(json.encode, payloads))

-- interactions --------------------------------------------------------------------------------

local GUILD = "g1"
local member = { roles = {}, permissions = Permissions.toString(Permissions.All), user = { id = "1", username = "owner" } }

local function interaction(t: number, data: any, extra: any?)
	local i = {
		id = "i" .. tostring(math.random(1, 1e9)),
		token = "tok",
		type = t,
		data = data,
		guild_id = GUILD,
		channel_id = "c1",
		member = member,
		app_permissions = Permissions.toString(Permissions.All),
		context = 0,
		authorizing_integration_owners = { ["0"] = GUILD },
		locale = "en-US",
	}
	for k, v in extra or {} do
		i[k] = v
	end
	return i
end

-- /ping
reset()
bot:_handleInteraction(interaction(2, { name = "ping", type = 1 }))
check("ping responds", last() and last().route == "/interactions/" .. "" .. string.match(last().route, "/interactions/([^/]+)") .. "/tok/callback")
check("ping type 4", last().body.type == 4 and string.find(last().body.data.content, "Pong"), last().body)

-- /config prefix set value:?
reset()
bot:_handleInteraction(interaction(2, {
	name = "config",
	type = 1,
	options = { { type = 2, name = "prefix", options = { { type = 1, name = "set", options = { { type = 3, name = "value", value = "?" } } } } } },
}))
check("config group runs", last().body.data.content == "Prefix set to `?`.", last().body)
check("store kept", bot.store.settings[GUILD].prefix == "?")

-- autocomplete for /color name:bl
reset()
bot:_handleInteraction(interaction(4, {
	name = "color",
	type = 1,
	options = { { type = 3, name = "name", value = "bl", focused = true } },
}))
local choices = last().body.data.choices
check("autocomplete type 8", last().body.type == 8)
check("autocomplete filtered", #choices == 2 and choices[1].name == "black" and choices[2].name == "blue", choices)

-- function autocomplete sees the other options
reset()
bot:_handleInteraction(interaction(4, {
	name = "color",
	type = 1,
	options = { { type = 3, name = "name", value = "red" }, { type = 3, name = "shade", value = "", focused = true } },
}))
check("autocomplete fn", last().body.data.choices[1].name == "red (light)", last().body)

-- /counter then click +1 (an inline handler)
reset()
bot:_handleInteraction(interaction(2, { name = "counter", type = 1 }))
local body = last().body
check("counter is v2", bit32.band(body.data.flags or 0, 32768) ~= 0, body)
local row = body.data.components[1].components[3]
check("buttons in a row", row.type == 1 and #row.components == 3, row)
local plusId = row.components[2].custom_id
check("inline id", string.sub(plusId, 1, 4) == "~cb:")
reset()
bot:_handleInteraction(interaction(3, { custom_id = plusId, component_type = 2 }, { message = { id = "reply1", channel_id = "c1" } }))
check("counter update", last().body.type == 7 and last().body.data.components[1].components[1].content == "# 1", last().body)

-- registered component handler with params: roles:pick
reset()
responses["^PUT /guilds/g1/members/1/roles/"] = true
bot:_handleInteraction(interaction(3, { custom_id = "roles:pick", component_type = 3, values = { "r1" } }, {
	message = { id = "m", channel_id = "c1", components = { { type = 1, components = { { type = 3, custom_id = "roles:pick", options = { { label = "A", value = "r1" }, { label = "B", value = "r2" } } } } } } },
}))
local sawDefer, sawAdd, sawEdit = false, false, false
for _, c in calls do
	if c.body and c.body.type == 5 then
		sawDefer = true
	end
	if c.method == "PUT" and c.route == "/guilds/g1/members/1/roles/r1" then
		sawAdd = true
	end
	if c.method == "PATCH" and string.find(c.route, "@original") then
		sawEdit = c.body.content == "Done: 1 added, 0 removed."
	end
end
check("component defer", sawDefer)
check("component adds role", sawAdd)
check("component replies after defer", sawEdit, calls)

-- user command
reset()
bot:_handleInteraction(interaction(2, {
	name = "User Info",
	type = 2,
	target_id = "5",
	resolved = { users = { ["5"] = { id = "5", username = "someone" } }, members = { ["5"] = { roles = { "r1" } } } },
}))
check("user command ephemeral", bit32.band(last().body.data.flags, 64) ~= 0, last().body)

-- message command (user install outside the bot's servers: no reaction)
reset()
bot:_handleInteraction(interaction(2, {
	name = "Quote",
	type = 3,
	target_id = "77",
	resolved = { messages = { ["77"] = { id = "77", channel_id = "c1", content = "hello world", author = { id = "5", username = "someone" } } } },
}, { context = 2, authorizing_integration_owners = { ["1"] = "1" }, guild_id = nil }))
check("quote replies", calls[1].body.type == 4)
check("quote doesn't react without the bot", #calls == 1, calls)

-- modal via ctx:prompt
reset()
task.spawn(function()
	bot:_handleInteraction(interaction(2, { name = "feedback", type = 1 }))
end)
local modal = last().body
check("modal shown", modal.type == 9 and modal.data.components[1].type == 18, modal)
local modalId = modal.data.custom_id
reset()
bot:_handleInteraction(interaction(5, {
	custom_id = modalId,
	components = {
		{ type = 18, component = { type = 3, custom_id = "topic", values = { "Idea" } } },
		{ type = 18, component = { type = 4, custom_id = "text", value = "more cats" } },
	},
}))
task.wait()
check("modal submit reply", last() and last().body.data.content == "Thanks! Your **Idea** feedback was recorded.", calls)

-- /help paginates; press next
reset()
task.spawn(function()
	bot:_handleInteraction(interaction(2, { name = "help", type = 1 }))
end)
local page = last().body.data
local navRow = page.components[#page.components]
check("help has pages", navRow.type == 1 and navRow.components[2].label:match("^1 / %d+$"), page)
local nextId = navRow.components[3].custom_id
reset()
bot:_handleInteraction(interaction(3, { custom_id = nextId, component_type = 2 }, { message = { id = "reply1", channel_id = "c1" } }))
check("help next page", last().body.type == 7 and last().body.data.components[#last().body.data.components].components[2].label:match("^2 / "), last().body)

-- errors in handlers are caught and reported
bot:command({ name = "boom", description = "x", run = function()
	error("kaboom")
end })
local reported = nil
bot:onError(function(err)
	reported = err
end)
reset()
bot:_handleInteraction(interaction(2, { name = "boom", type = 1 }))
check("error handler", reported and string.find(reported, "kaboom"))
check("error reply", last().body.data and string.find(last().body.data.content, "Something went wrong"), last().body)

-- prefix commands -----------------------------------------------------------------------------

local function message(content: string, extra: any?)
	local m = {
		id = "msg" .. tostring(math.random(1, 1e9)),
		channel_id = "c1",
		guild_id = GUILD,
		content = content,
		author = { id = "1", username = "owner" },
		member = { roles = {} },
		mentions = {},
		attachments = {},
	}
	for k, v in extra or {} do
		m[k] = v
	end
	return m
end

-- a cached guild for permission checks
bot.cache.guilds[GUILD] = { id = GUILD, owner_id = "1", roles = { { id = GUILD, permissions = "0" } } }
bot.cache.channels["c1"] = { id = "c1", guild_id = GUILD, type = 0 }
bot.cache.members[GUILD] = { ["999"] = { roles = {} } }

reset()
bot:_handleMessage(message("!ping"))
check("prefix ping", last().body.content and string.find(last().body.content, "Pong") and last().body.message_reference ~= nil, last())

reset()
bot:_handleMessage(message("!LATENCY"))
check("alias + case", #calls == 1)

reset()
bot:_handleMessage(message("<@999> ping"))
check("mention prefix", #calls == 1)

reset()
bot:_handleMessage(message("!config prefix set >>"))
check("prefix subcommand group", last().body.content == "Prefix set to `>>`.", last().body)

reset()
bot:_handleMessage(message("!config"))
check("subcommand usage", string.find(last().body.content, "Usage: `!config <show|prefix>`"), last().body)

reset()
bot:_handleMessage(message("!color"))
check("missing arg", string.find(last().body.content, "`name` is required"), last().body)

reset()
bot:_handleMessage(message("!userinfo <@5>", { mentions = { { id = "5", username = "someone" } } }))
responses["^GET /guilds/g1/members/5"] = { roles = {}, user = { id = "5", username = "someone" } }
check("userinfo via mention", #calls >= 1)

-- purge: the bot lacks ManageMessages (everyone role has 0 and the bot has no roles)
reset()
bot.cache.guilds[GUILD].owner_id = "someone-else"
table.insert(bot.cache.guilds[GUILD].roles, { id = "modrole", permissions = Permissions.toString(Permissions.All) })
bot:_handleMessage(message("!purge 5", { member = { roles = { "modrole" } } }))
check("bot permission check", last().body.content and string.find(last().body.content, "I need these permissions"), last().body)
bot.cache.guilds[GUILD].owner_id = "1"

-- members without the permission
reset()
bot:_handleMessage(message("!config show", { author = { id = "2", username = "pleb" } }))
check("member permission check", string.find(last().body.content, "You need these permissions: Manage Guild"), last().body)

-- cooldown (owners skip cooldowns; use another user)
bot.cache.guilds[GUILD].roles[1].permissions = Permissions.toString(Permissions.All)
bot.cache.members[GUILD]["999"] = { roles = {} }
responses["^GET /channels/c1/messages$"] = { { id = "a" }, { id = "b" } }
reset()
task.spawn(bot._handleMessage, bot, message("!purge 2", { author = { id = "3", username = "mod" } }))
reset()
bot:_handleMessage(message("!purge 2", { author = { id = "3", username = "mod" } }))
check("cooldown", last().body.content and string.find(last().body.content, "Slow down"), last().body)

-- tokenizer and parser ------------------------------------------------------------------------

local tokens = commands.tokenize('one "two three" four')
check("tokenize quotes", #tokens == 3 and tokens[2].value == "two three", tokens)

local banDef = bot.prefixCommands["ban"]
local values, err = commands.parseArgs(banDef, "<@5> being rude in chat", {
	user = function(id)
		return { id = id, username = "u" .. id }
	end,
}, {})
check("ban args skip optional int", values and values.user.id == "5" and values.days == nil and values.reason == "being rude in chat", { values, err })
values = commands.parseArgs(banDef, "<@5> 3 spam", { user = function(id)
	return { id = id }
end }, {})
check("ban args with int", values and values.days == 3 and values.reason == "spam", values)
local _, rangeErr = commands.parseArgs(banDef, "<@5> 30", { user = function(id)
	return { id = id }
end }, {})
-- 30 is out of range for days, so it is treated as the reason
check("out of range optional falls through", rangeErr == nil)

-- permissions ---------------------------------------------------------------------------------

check("perm bit 40", Permissions.has(Permissions.resolve({ "ModerateMembers" }), "ModerateMembers"))
check("perm missing", #Permissions.missing(Permissions.resolve({ "SendMessages" }), { "SendMessages", "BanMembers" }) == 1)
check("perm string", Permissions.toString(Permissions.resolve("PinMessages")) == "2251799813685248")
local computed = Permissions.compute(
	{ id = "g", owner_id = "x", roles = { { id = "g", permissions = Permissions.toString(Permissions.resolve({ "ViewChannel", "SendMessages" })) } } },
	{ roles = {} },
	"u",
	{ permission_overwrites = { { id = "g", type = 0, allow = "0", deny = Permissions.toString(Permissions.Flags.SendMessages) } } }
)
check("overwrite deny", Permissions.has(computed, "ViewChannel") and not Permissions.has(computed, "SendMessages"))

-- components and messages ---------------------------------------------------------------------

local messages = require("../lib/messages")
local okV2 = pcall(messages.build, { content = "x", components = { ui.text("y") } })
check("v2 rejects content", not okV2)
local b = messages.build({ content = "hi", components = { ui.button({ label = "a", customId = "a" }), ui.button({ label = "b", customId = "b" }) } })
check("loose buttons wrapped", #b.components == 1 and #b.components[1].components == 2, b)
local files
b, files = messages.build({ components = { ui.file("attachment://a.txt") }, files = { { name = "a.txt", data = "hello" } } })
check("files passed", files and files[1].name == "a.txt")
check("emoji parse", ui.emoji("<a:wave:123>").animated == true and ui.emoji("👍").name == "👍")
check("color parse", ui.color("#ff0000") == 0xff0000)
local disabled = ui.disableAll({ ui.row(ui.button({ label = "x", customId = "x" }), ui.link("y", "https://e.com")) })
check("disableAll", disabled[1].components[1].disabled == true and disabled[1].components[2].disabled == nil)

-- HTTP signature check works with the runtime's ed25519 ---------------------------------------

local public, private = crypto.keypair("ed25519")
local sig = crypto.sign(private, "123" .. "{}")
check("ed25519 roundtrip", crypto.verify(public, "123{}", sig))

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	require("@sonata/process").exit(1)
end
require("@sonata/process").exit(0)
