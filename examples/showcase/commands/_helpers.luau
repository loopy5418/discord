-- files starting with _ aren't loaded as commands, so they can hold shared code
local helpers = {}

-- groups a list by a field, keeping the groups sorted by key
function helpers.groupBy(list: { any }, field: string): { { key: string, items: { any } } }
	local byKey = {}
	local groups = {}
	for _, item in list do
		local key = tostring(item[field])
		local group = byKey[key]
		if group == nil then
			group = { key = key, items = {} }
			byKey[key] = group
			table.insert(groups, group)
		end
		table.insert(group.items, item)
	end
	table.sort(groups, function(a, b)
		return a.key < b.key
	end)
	return groups
end

return helpers
