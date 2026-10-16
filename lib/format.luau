--[[
	Markdown and mention helpers

	    local fmt = require("@discord/lib/format")
	    fmt.user(id) --> "<@id>"
	    fmt.timestamp(os.time() + 60, "R") --> "<t:...:R>" (in a minute)
	    fmt.codeblock("print(1)", "lua")
]]

local fmt = {}

function fmt.user(id: any): string
	return `<@{if type(id) == "table" then id.id else id}>`
end

function fmt.channel(id: any): string
	return `<#{if type(id) == "table" then id.id else id}>`
end

function fmt.role(id: any): string
	return `<@&{if type(id) == "table" then id.id else id}>`
end

-- a clickable slash command: fmt.command("ban", id) or fmt.command("config set", id)
function fmt.command(name: string, id: string): string
	return `</{name}:{id}>`
end

function fmt.emoji(name: string, id: string, animated: boolean?): string
	return `<{if animated then "a" else ""}:{name}:{id}>`
end

-- styles: t T d D f F R (see enums.TimestampStyle); `t` is unix seconds
function fmt.timestamp(t: number?, style: string?): string
	local seconds = math.floor(t or os.time())
	if style then
		return `<t:{seconds}:{style}>`
	end
	return `<t:{seconds}>`
end

function fmt.bold(s: string): string
	return `**{s}**`
end

function fmt.italic(s: string): string
	return `*{s}*`
end

function fmt.underline(s: string): string
	return `__{s}__`
end

function fmt.strike(s: string): string
	return `~~{s}~~`
end

function fmt.spoiler(s: string): string
	return `||{s}||`
end

function fmt.code(s: string): string
	return "`" .. s .. "`"
end

function fmt.codeblock(s: string, language: string?): string
	return "```" .. (language or "") .. "\n" .. s .. "\n```"
end

function fmt.quote(s: string): string
	return "> " .. (string.gsub(s, "\n", "\n> "))
end

function fmt.blockquote(s: string): string
	return ">>> " .. s
end

-- level 1-3
function fmt.heading(s: string, level: number?): string
	return string.rep("#", level or 1) .. " " .. s
end

-- small grey text
function fmt.subtext(s: string): string
	return "-# " .. s
end

function fmt.link(text: string, url: string): string
	return `[{text}]({url})`
end

function fmt.list(items: { string }, ordered: boolean?): string
	local out = {}
	for i, item in items do
		table.insert(out, if ordered then `{i}. {item}` else `- {item}`)
	end
	return table.concat(out, "\n")
end

-- escapes markdown so user text shows literally
function fmt.escape(s: string): string
	return (string.gsub(s, "([\\%*_~`|>#%-%[%]%(%)])", "\\%1"))
end

-- stops @everyone/@here from pinging, for echoing user text
function fmt.escapeMentions(s: string): string
	return (string.gsub(s, "@(everyone)", "@\u{200b}%1"):gsub("@(here)", "@\u{200b}%1"))
end

-- avatar url for a user object (falls back to the default avatar)
function fmt.avatar(user: any, size: number?): string
	local query = if size then `?size={size}` else ""
	if user.avatar then
		local ext = if string.sub(user.avatar, 1, 2) == "a_" then "gif" else "png"
		return `https://cdn.discordapp.com/avatars/{user.id}/{user.avatar}.{ext}{query}`
	end
	-- new usernames: (id >> 22) % 6, legacy: discriminator % 5
	local index
	if user.discriminator and user.discriminator ~= "0" then
		index = (tonumber(user.discriminator) or 0) % 5
	else
		index = math.floor((tonumber(user.id) or 0) / 4194304) % 6
	end
	return `https://cdn.discordapp.com/embed/avatars/{index}.png`
end

-- guild icon url, or nil if the guild has none
function fmt.guildIcon(guild: any, size: number?): string?
	if not guild.icon then
		return nil
	end
	local ext = if string.sub(guild.icon, 1, 2) == "a_" then "gif" else "png"
	return `https://cdn.discordapp.com/icons/{guild.id}/{guild.icon}.{ext}` .. (if size then `?size={size}` else "")
end

-- the name to show for a user: server nickname, then global name, then username
function fmt.displayName(user: any, member: any?): string
	if member and member.nick and member.nick ~= "" then
		return member.nick
	end
	return user.global_name or user.username or "unknown"
end

-- unix seconds a snowflake was created at
function fmt.snowflakeTime(id: string): number
	return math.floor((tonumber(id) or 0) / 4194304 / 1000) + 1420070400
end

-- "1h 2m 3s"
function fmt.duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local parts = {}
	for _, unit in { { 86400, "d" }, { 3600, "h" }, { 60, "m" }, { 1, "s" } } do
		local n = math.floor(seconds / unit[1])
		if n > 0 then
			table.insert(parts, `{n}{unit[2]}`)
			seconds -= n * unit[1]
		end
	end
	return if #parts == 0 then "0s" else table.concat(parts, " ")
end

-- "10m", "1h30m", "2d" -> seconds, or nil if it can't be read
function fmt.parseDuration(text: string): number?
	local units = { s = 1, m = 60, h = 3600, d = 86400, w = 604800 }
	local total, found = 0, false
	for amount, unit in string.gmatch(string.lower(text), "(%d+%.?%d*)%s*(%a)") do
		local mult = units[unit]
		if mult == nil then
			return nil
		end
		total += (tonumber(amount) or 0) * mult
		found = true
	end
	if not found then
		return tonumber(text)
	end
	return total
end

-- cuts `s` to `max` characters with an ellipsis, for embed and component limits
function fmt.truncate(s: string, max: number): string
	if #s <= max then
		return s
	end
	return string.sub(s, 1, max - 3) .. "..."
end

return table.freeze(fmt)
