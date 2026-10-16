--[[
Docs:
https://sonata.5418.org/docs/guide/manifest/
https://sonata.5418.org/docs/guide/packages/
]]

return {
    name = "discord",
    version = "0.1.0",
    description = "Discord bots for Sonata: docs url here",
    entrypoint = "init.luau",
    authors = { "github.com/loopy5418" },
    dependencies = {
        {
            name = "httpx",
            url = "https://github.com/loopy5418/httpx",
        },
    },
    build = {
        output = "dist/discord",
        libraries = { "task", "json", "fs", "path", "crypto", "process", "datetime", "pocket" },
        assets = { "examples/showcase/commands", "examples/showcase/components", "examples/showcase/events" },
    },
}
