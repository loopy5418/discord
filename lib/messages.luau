--[[
	Turns what users pass to reply/send/edit into Discord's message JSON

	Accepted input: a string (content), a component/embed table, or an options table:

	    {
	        content = "text",
	        embeds = { ui.embed(...) }, embed = ui.embed(...),
	        components = { ... },          -- buttons/selects at the top level are put in rows
	        files = { { name = "a.png", data = bytes } | { name = "a.png", path = "a.png" } },
	        ephemeral = true,              -- interactions only
	        silent = true,                 -- no push notification
	        suppressEmbeds = true,
	        tts = true,
	        poll = ui.poll(...),
	        stickers = { id },
	        allowedMentions = { parse = { "users" }, users = { id }, roles = { id }, repliedUser = false },
	        reply = messageId | message | { messageId, channelId, failIfNotExists },
	        flags = number,                -- combined with the flags above
	        v2 = true,                     -- force IsComponentsV2 (set automatically otherwise)
	        attachments = { ... },         -- keep/replace existing attachments when editing
	        nonce = "...", enforceNonce = true,
	    }
]]

local json = require("@sonata/json")
local enums = require("./enums")
local ui = require("./components")

local Flags = enums.MessageFlags

local messages = {}

local function hasFlag(flags: number, flag: number): boolean
	return bit32.band(flags, flag) ~= 0
end

function messages.allowedMentions(value: any): any
	if value == nil then
		return nil
	end
	if value == false then
		return json.object({ parse = json.array() })
	end
	local out = json.object()
	if value.parse then
		out.parse = json.array(table.clone(value.parse))
	elseif value.users == nil and value.roles == nil then
		out.parse = json.array()
	end
	if value.users then
		out.users = json.array(table.clone(value.users))
	end
	if value.roles then
		out.roles = json.array(table.clone(value.roles))
	end
	local replied = value.repliedUser
	if replied == nil then
		replied = value.replied_user
	end
	if replied ~= nil then
		out.replied_user = replied
	end
	return out
end

-- whether a table looks like a single component or embed rather than an options table
local function isComponent(t: any): boolean
	return type(t) == "table" and type(t.type) == "number"
end

--[[
	Returns (body, files). `defaults` fills in what the input leaves out: `allowedMentions`,
	`ephemeral`. `forEdit` leaves out fields edits can't change (tts, nonce, reply...).
]]
function messages.build(input: any, defaults: { [string]: any }?, forEdit: boolean?): ({ [string]: any }, { any }?)
	local defaultsTF = defaults or {}
	local o: { [string]: any }
	if type(input) == "string" or type(input) == "number" then
		o = { content = tostring(input) }
	elseif isComponent(input) then
		o = { components = { input } }
	elseif type(input) == "table" and input.title ~= nil and input.content == nil and input.components == nil and input.description ~= nil then
		-- an embed
		o = { embeds = { input } }
	elseif type(input) == "table" then
		o = input
	else
		error(`can't send {typeof(input)} as a message`, 3)
	end

	local body: { [string]: any } = {}
	if o.content ~= nil then
		body.content = tostring(o.content)
	end

	local embeds = o.embeds
	if o.embed then
		embeds = { o.embed }
	end
	if embeds then
		body.embeds = json.array(embeds)
	end

	if o.components then
		local components = ui.normalize(o.components)
		body.components = json.array(components)
	end

	local flags = o.flags or 0
	local ephemeral = o.ephemeral
	if ephemeral == nil then
		ephemeral = defaultsTF.ephemeral
	end
	if ephemeral and not forEdit then
		flags = bit32.bor(flags, Flags.Ephemeral)
	end
	if o.silent then
		flags = bit32.bor(flags, Flags.SuppressNotifications)
	end
	if o.suppressEmbeds then
		flags = bit32.bor(flags, Flags.SuppressEmbeds)
	end
	if o.v2 or ui.isV2(o.components) then
		flags = bit32.bor(flags, Flags.IsComponentsV2)
	end
	if hasFlag(flags, Flags.IsComponentsV2) then
		if body.content ~= nil or body.embeds ~= nil then
			error("messages with components v2 can't have content or embeds; put the text in ui.text(...) instead", 3)
		end
	end
	if flags ~= 0 then
		body.flags = flags
	end

	if o.poll then
		body.poll = o.poll
	end
	if o.stickers then
		body.sticker_ids = json.array(o.stickers)
	end
	if o.attachments then
		body.attachments = json.array(o.attachments)
	end

	local mentions = o.allowedMentions or o.allowed_mentions
	if mentions == nil then
		mentions = defaultsTF.allowedMentions
	end
	if mentions ~= nil then
		body.allowed_mentions = messages.allowedMentions(mentions)
	end

	if not forEdit then
		if o.tts then
			body.tts = true
		end
		if o.nonce then
			body.nonce = o.nonce
			body.enforce_nonce = o.enforceNonce
		end
		local ref = o.reply or o.messageReference
		if ref then
			if type(ref) == "string" then
				body.message_reference = { message_id = ref, fail_if_not_exists = false }
			elseif ref.id and ref.channel_id then
				-- a message object
				body.message_reference = { message_id = ref.id, channel_id = ref.channel_id, guild_id = ref.guild_id, fail_if_not_exists = false }
			else
				body.message_reference = {
					message_id = ref.messageId or ref.message_id,
					channel_id = ref.channelId or ref.channel_id,
					fail_if_not_exists = ref.failIfNotExists or false,
				}
			end
		end
	end

	local files = o.files
	if o.file then
		files = { o.file }
	end
	return body, files
end

return messages
