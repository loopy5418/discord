# discord

A Discord bot framework for [Sonata](https://sonata.5418.org).

```sh
sn pkg add github.com/loopy5418/discord
```

```luau
local discord = require("@discord")

local bot = discord.new({ token = TOKEN, prefix = "!" })

bot:command({
    name = "ping",
    description = "Pong!",
    prefix = true, -- /ping and !ping
    run = function(ctx)
        ctx:reply("Pong!")
    end,
})

bot:load("commands", "components", "events")
bot:start()
```

## Example bots

Run directly, this project is a launcher for the example bots:

```sh
sn run                                   # list the examples
sn run -- whoami --token <token>         # check a token and the gateway connection
sn run -- ping --guild <server id>       # the smallest bot
sn run -- showcase                       # every feature, loaded from folders
sn run -- http --port 8080               # interactions over HTTP, no gateway
sn run -- selftest                       # offline tests, no token needed

sn build && ./dist/discord whoami        # the same, as a built program
sn run --entry examples/ping/main.luau -- --token <token>   # one example on its own
```

The token comes from `--token`, `DISCORD_TOKEN`, or a file named `token` in the working directory or the project root. For a built program, the project root is the folder the executable is in. `--guild` registers the example's commands in that server only, so changes show up instantly.

- `ping`, `showcase` and `http` register their slash commands on the application when they start.
- `whoami` only reads, connects to the gateway, and disconnects.

## Layout

| Path | What it holds |
| --- | --- |
| `init.luau` | The package entry: `require("@discord")`. Run directly, it starts `examples/launcher.luau` |
| `lib/init.luau` | `Bot`: registration, loading, routing, checks, cooldowns, middleware, command sync, running |
| `lib/context.luau` | `Context`, the first argument of every handler |
| `lib/commands.luau` | Command validation, registration JSON, option resolution, prefix argument parsing |
| `lib/components.luau` | Component builders (classic and v2), modals, embeds, polls, inline handlers |
| `lib/messages.luau` | Turns `reply`/`send`/`edit` input into message JSON |
| `lib/api.luau` | REST endpoint wrappers (`api.channels`, `api.guilds`, `api.users`, ...) |
| `lib/rest.luau` | HTTP client with rate limits, retries, file uploads and audit log reasons |
| `lib/cache.luau` | Guilds, roles, channels, users and members seen on the gateway |
| `lib/permissions.luau` | Permission flags (wider than 32 bits) and permission computation |
| `lib/format.luau` | Mentions, timestamps, markdown, avatars, durations |
| `lib/enums.luau` | Discord constants |
| `lib/loader.luau` | Loads definitions from files, folders and globs, including in built programs |
| `lib/http.luau` | HTTP interactions endpoint (ed25519-verified) |
| `lib/types.luau` | Types for every definition, option and context member |
| `lib/gateway/` | The gateway connection, opcodes and intents |
| `examples/` | The example bots and their launcher |
| `tests/offline.luau` | Offline tests with a fake REST client |

Modules are also reachable on their own: `require("@discord/lib/components")`.

## Commands

```luau
{
    name = "ban",
    description = "Ban a member",
    type = "slash",             -- "slash" (default) | "user" | "message" | "prefix"
    prefix = true,              -- also a prefix command (a hybrid)
    aliases = { "b" },
    options = {
        { name = "user", type = "user", description = "Who", required = true },
        { name = "days", type = "integer", min = 0, max = 7 },
        { name = "reason", type = "string" }, -- the last string option takes the rest of the text
    },
    permissions = { "BanMembers" },    -- Discord enforces it for slash; checked at runtime for prefix
    botPermissions = { "BanMembers" },
    guildOnly = true, ownerOnly = false, nsfw = false,
    install = { "guild", "user" },     -- user-installed app support
    contexts = { "guild", "botDm", "privateChannel" },
    guilds = { "123" },                -- register only there
    cooldown = 5,                      -- or { seconds, scope = "user" | "guild" | "channel" | "global" }
    checks = { function(ctx) return ctx.user.id ~= "1", "not you" end },
    ephemeral = true,                  -- default visibility of replies
    defer = true,                      -- or "ephemeral"
    run = function(ctx, args) end,
}
```

- **Option types:** `string`, `integer`, `number`, `boolean`, `user`, `member` (resolves to the guild member), `channel`, `role`, `mentionable`, `attachment`.
- **Option fields:** `required`, `default`, `choices`, `min`/`max`, `minLength`/`maxLength`, `channelTypes`, `autocomplete` (a function, or a list that is filtered as the user types), `rest`.
- **Subcommands:** `subcommands = { { name, description, options, run } }`. An entry with its own `subcommands` is a group. Prefix commands route the same way: `!config prefix set ?`.
- **Context menus:** `type = "user"` gets `run(ctx, targetUser)`. `type = "message"` gets `run(ctx, targetMessage)`.
- **Prefix arguments:** mentions, ids and role names resolve to objects. `"quoted text"` counts as one argument. Optional typed arguments that don't match are skipped. Errors reply with an auto-generated usage line.

## Context

Every handler's first argument. Fields depend on `ctx.kind`, which is one of `slash`, `user`, `message`, `prefix`, `component`, `modal`, `autocomplete` or `event`. `types.luau` lists every field.

**Responding:**
- `reply`: the first response, then the deferred message, then follow-ups. For prefix commands it replies to the command message.
- `defer`, `deferUpdate`, `update`, `edit`, `deleteReply`, `fetchReply`, `followUp`, `send`.
- `showModal`, `prompt` (opens a modal and waits for it), `respond` (autocomplete), `error`.

**Messages:** `react`, `typing`, `dm`.

**Waiting:**
- `awaitComponent`, `collect`, `awaitMessage`, `waitFor`.
- `confirm(question)` returns true, false, or nil on timeout.
- `paginate(pages)` shows pages with previous/next buttons.

**Permissions:** `hasPermission`, `botHasPermission`, `memberPermissions`, `botPermissions`, `isOwner`.

**Lookups:** `fetchGuild`, `fetchChannel`, `fetchMember`, `fetchUser`, `fetchRole`. They check the cache first.

**Data:**
- `options`/`args`, `fields` (modals), `values` and `selected()` (selects), `params` (custom id parts), `uploads(id)` (modal file uploads).
- `target`/`targetMember` (context menus), `message`, `user`, `member`, `guildId`, `channelId`, `locale`.
- `isUserInstall`, `botPresent`.

**Libraries:** `ctx.api`, `ctx.rest`, `ctx.ui`, `ctx.fmt`, `ctx.enums`, `ctx.permissions`, `ctx.cache`, `ctx.bot`.

**State:** `ctx.store` lasts as long as the bot. `ctx.state` lasts for one invocation.

## Components

```luau
local ui = discord.ui
ctx:reply({
    components = {
        ui.container({ accent = "#5865F2",
            ui.text("# Title"),
            ui.section({ "Some text", accessory = ui.thumbnail(url) }),
            ui.gallery({ url1, url2 }),
            ui.separator({ spacing = "large" }),
            ui.row(
                ui.button({ label = "Vote", customId = "vote:yes" }),         -- handled by a registered component
                ui.button({ label = "Now", run = function(c) c:update("hi") end }) -- inline handler
            ),
        }),
    },
})
```

- Messages that contain v2 components get the `IsComponentsV2` flag automatically.
- Loose buttons and selects get wrapped in action rows.
- **Files:** pass `files = { { name = "a.png", data = bytes } }` or `{ name, path }`. Refer to them as `attachment://a.png`.
- **Modals:** `ui.modal({ title, ...inputs })` with `ui.label`, `ui.textInput`, selects, `ui.fileUpload`, `ui.radioGroup`, `ui.checkboxGroup` and `ui.checkbox`.
- **Other builders:** `ui.embed`, `ui.poll`, `ui.disableAll`, `ui.find`.

## Component and modal handlers

```luau
return discord.component({
    customId = "vote",          -- handles "vote", "vote:yes", "vote:no:123", ...
    defer = "update",           -- optional: deferUpdate / "reply" / "ephemeral"
    run = function(ctx, choice, extra) -- the parts of the custom id after "vote:"
        ctx:update(`You picked {choice}`)
    end,
})
-- or match = "^ticket_(%d+)$" (the captures become the parameters)
-- modals: discord.modal({ customId = "report", run = function(ctx, fields) end })
```

The router checks waiting collectors (`awaitComponent`, `prompt`, ...) first, then inline `run` handlers, then registered handlers.

## Loading from files

```luau
bot:load("commands")             -- a folder, recursively
bot:load("commands/ping")        -- a file (extension optional)
bot:load("plugins/*.luau")       -- a glob
bot:load(require("./extra"))     -- an already-required module
```

- Relative paths resolve from the calling file.
- Files and folders starting with `_` or `.` are skipped, so you can keep helpers there.
- A folder with an `init.luau` loads as one module.

A module can return any of these:
- a definition (tag it with `discord.command`, `discord.component`, `discord.modal` or `discord.event`, or leave it untagged; the fields identify it)
- a list of definitions
- a table with `commands`, `components`, `modals` and/or `events` lists
- a function, which is called as a plugin: `fn(bot)`

Called on a bot, the same helpers register right away: `bot:command({...})`, `bot:component({...})`.

Changes take effect on restart, since `require` caches modules.

### In built programs

`sn build` compiles every `.luau` file into the program, but there are no folders to walk. The loader lists folders from the program's assets instead, so add each folder you load to your manifest:

```luau
build = { assets = { "commands", "components", "events" } }
```

Single files (`bot:load("commands/ping")`) work without an asset entry.

By default the root project's assets are listed. A package that loads folders of its own passes a lister, written in its own code, because pocket answers for the package whose function calls it:

```luau
local pocket = require("@sonata/pocket")
local bot = discord.new({ token = TOKEN, assets = function(folder) return pocket.list(folder) end })
```

## Events, middleware, errors

```luau
bot:on("messageCreate", function(ctx, message) end)  -- or "MESSAGE_CREATE"; "*" gets (ctx, name, data)
bot:once("READY", function(ctx, data) end)
local data = bot:waitFor("MESSAGE_REACTION_ADD", function(d) return d.user_id == id end, 30)

bot:use(function(ctx, next) -- runs around every command, component and modal handler
    if ctx.user.id == BANNED then return ctx:error("no") end
    next()
end)
bot:onError(function(err, ctx) end)
```

## Bot options

| Option | Default | |
| --- | --- | --- |
| `token` | `DISCORD_TOKEN` | |
| `intents` | Guilds, GuildMessages, DirectMessages (+ MessageContent with a prefix) | |
| `prefix` | none | a string, a list, or `function(message, bot)` (may yield) |
| `mentionPrefix` | `true` | `@bot ping` |
| `caseInsensitive`, `ignoreBots` | `true` | |
| `owners` | the app's owner or team | for `ownerOnly` |
| `devGuild` | | registers every command in that guild (instant updates) |
| `syncCommands` | `true` | syncs changed commands on READY; `"force"` always syncs |
| `commandCache` | `.commands.lock.json` | hashes of synced commands |
| `defaultInstall`, `defaultContexts` | | applied to commands that don't set them |
| `allowedMentions` | users only, no reply ping | |
| `autoDefer` | `true` | defers if a command hasn't answered after about 2.3s |
| `errorMessage` | generic text | shown when a handler errors; `false` to hide |
| `http` / `gateway` | | `http = { port, publicKey }` for HTTP interactions (the key defaults to the application's); `gateway = false` for HTTP-only |
| `strictIntents` | `false` | without it, privileged intents the developer portal hasn't enabled are dropped with a warning instead of failing with 4014 |
| `assets` | the root project's assets | lists asset files under a folder, for `bot:load` in built programs |

## Other methods

- **Running:** `bot:run()` returns `ok, reason`. `bot:start()` exits the process on a fatal error. `bot:stop()`.
- **Commands:** `bot:syncCommands({ force })`, `bot:clearCommands(guildId)`, `bot:helpEntries(prefix)`.
- **Presence:** `bot:setStatus(status, text, type)`, `bot:setPresence(raw)`.
- **Lookups:** `bot:fetchUser`, `bot:fetchMember`, `bot:fetchChannel`, `bot:fetchGuild`.
- **Gateway:** `bot.gateway:requestGuildMembers(guildId, options)`, and `bot.gateway.latency`.
- **Application:** `bot:application()` (cached), `bot:disallowedIntents()`.
- **REST without a bot:** `discord.makeApi(discord.Rest.new(token))`.
