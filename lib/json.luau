--[[
	discord sends null for fields that do exist, but are empty
	but @sonata/json returns json.null, which countrs as true
	so this is a function to not do that
]]

local json = require("@sonata/json")

local function stripNull(value: any): any
	if type(value) == "table" then
		for k, v in value do
			if v == json.null and type(k) == "string" then
				value[k] = nil
			else
				stripNull(v)
			end
		end
	end
	return value
end

local function decode(text: string): any
	return stripNull(json.decode(text))
end

return {
	stripNull = stripNull,
	decode = decode,
}
