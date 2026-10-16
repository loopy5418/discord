--[[
	Interactions over HTTP: no gateway connection. Discord POSTs each interaction to a public
	URL you set in the developer portal (General Information > Interactions Endpoint URL), for
	example a tunnel to this port. The portal checks the URL when you save it, so start this first.

	    sn run -- http --token <token> [--port 8080] [--public-key <hex>]

	Prefix commands and gateway events don't exist in this mode.
]]

local discord = require("../../lib") -- in your project: require("@discord")
local config = require("../_config")

local cfg = config.require()
local ui = discord.ui

local bot = discord.new({
	token = cfg.token,
	gateway = false,
	http = { port = cfg.port, publicKey = cfg.publicKey }, -- the public key is fetched when not given
	devGuild = cfg.guild,
	debugRest = cfg.debugRest,
})

bot:command({
	name = "hello",
	description = "Answered over HTTP",
	install = { "guild", "user" },
	contexts = { "guild", "botDm", "privateChannel" },
	run = function(ctx)
		ctx:reply({
			components = {
				ui.container({
					ui.text(`Hello, {ctx:displayName()}! This came over HTTP.`),
					ui.row(ui.button({ label = "Again", run = function(c)
						c:update({ components = { ui.text("Still HTTP 👋") } })
					end })),
				}),
			},
		})
	end,
})

bot:start()
return nil
