--[[
	Discord constants (API v10)

	    local enums = require("@discord/lib/enums")
	    enums.ButtonStyle.Primary --> 1
	    enums.MessageFlags.Ephemeral --> 64

	Most builders and options also accept these by name ("primary", "ephemeral", ...), see
	`enums.resolve`.
]]

local enums = {}

-- https://docs.discord.com/developers/interactions/receiving-and-responding#interaction-object-interaction-type
enums.InteractionType = table.freeze({
	Ping = 1,
	ApplicationCommand = 2,
	MessageComponent = 3,
	Autocomplete = 4,
	ModalSubmit = 5,
})

-- https://docs.discord.com/developers/interactions/receiving-and-responding#interaction-response-object-interaction-callback-type
enums.CallbackType = table.freeze({
	Pong = 1,
	ChannelMessageWithSource = 4,
	DeferredChannelMessageWithSource = 5,
	DeferredUpdateMessage = 6,
	UpdateMessage = 7,
	AutocompleteResult = 8,
	Modal = 9,
	LaunchActivity = 12,
})

-- https://docs.discord.com/developers/interactions/application-commands#application-command-object-application-command-types
enums.CommandType = table.freeze({
	ChatInput = 1, -- slash commands
	User = 2, -- right click a user > Apps
	Message = 3, -- right click a message > Apps
	PrimaryEntryPoint = 4, -- activity launcher
})

-- https://docs.discord.com/developers/interactions/application-commands#application-command-object-application-command-option-type
enums.OptionType = table.freeze({
	SubCommand = 1,
	SubCommandGroup = 2,
	String = 3,
	Integer = 4,
	Boolean = 5,
	User = 6,
	Channel = 7,
	Role = 8,
	Mentionable = 9,
	Number = 10,
	Attachment = 11,
})

-- where a command can be installed
-- https://docs.discord.com/developers/resources/application#application-object-application-integration-types
enums.IntegrationType = table.freeze({
	GuildInstall = 0,
	UserInstall = 1,
})

-- where a command can be used
-- https://docs.discord.com/developers/interactions/receiving-and-responding#interaction-object-interaction-context-types
enums.InteractionContext = table.freeze({
	Guild = 0,
	BotDM = 1,
	PrivateChannel = 2, -- group DMs and DMs other than with the bot (user installs)
})

-- https://docs.discord.com/developers/components/reference#component-object-component-types
enums.ComponentType = table.freeze({
	ActionRow = 1,
	Button = 2,
	StringSelect = 3,
	TextInput = 4,
	UserSelect = 5,
	RoleSelect = 6,
	MentionableSelect = 7,
	ChannelSelect = 8,
	-- components v2 (layout and content), need the IsComponentsV2 message flag
	Section = 9,
	TextDisplay = 10,
	Thumbnail = 11,
	MediaGallery = 12,
	File = 13,
	Separator = 14,
	Container = 17,
	-- modal-only
	Label = 18,
	FileUpload = 19,
	RadioGroup = 21,
	CheckboxGroup = 22,
	Checkbox = 23,
})

enums.ButtonStyle = table.freeze({
	Primary = 1,
	Secondary = 2,
	Success = 3,
	Danger = 4,
	Link = 5,
	Premium = 6,
})

enums.TextInputStyle = table.freeze({
	Short = 1,
	Paragraph = 2,
})

enums.SeparatorSpacing = table.freeze({
	Small = 1,
	Large = 2,
})

-- https://docs.discord.com/developers/resources/message#message-object-message-flags
enums.MessageFlags = table.freeze({
	Crossposted = 1,
	IsCrosspost = 2,
	SuppressEmbeds = 4,
	SourceMessageDeleted = 8,
	Urgent = 16,
	HasThread = 32,
	Ephemeral = 64,
	Loading = 128,
	FailedToMentionSomeRolesInThread = 256,
	SuppressNotifications = 4096,
	IsVoiceMessage = 8192,
	HasSnapshot = 16384,
	IsComponentsV2 = 32768,
})

-- https://docs.discord.com/developers/resources/channel#channel-object-channel-types
enums.ChannelType = table.freeze({
	GuildText = 0,
	DM = 1,
	GuildVoice = 2,
	GroupDM = 3,
	GuildCategory = 4,
	GuildAnnouncement = 5,
	AnnouncementThread = 10,
	PublicThread = 11,
	PrivateThread = 12,
	GuildStageVoice = 13,
	GuildDirectory = 14,
	GuildForum = 15,
	GuildMedia = 16,
})

-- short names accepted by `channelTypes` options
enums.ChannelTypeAlias = table.freeze({
	text = 0,
	dm = 1,
	voice = 2,
	group = 3,
	category = 4,
	announcement = 5,
	news = 5,
	announcementThread = 10,
	thread = 11,
	publicThread = 11,
	privateThread = 12,
	stage = 13,
	directory = 14,
	forum = 15,
	media = 16,
})

enums.ActivityType = table.freeze({
	Playing = 0,
	Streaming = 1,
	Listening = 2,
	Watching = 3,
	Custom = 4,
	Competing = 5,
})

-- https://docs.discord.com/developers/resources/message#message-object-message-types
enums.MessageType = table.freeze({
	Default = 0,
	RecipientAdd = 1,
	RecipientRemove = 2,
	Call = 3,
	ChannelNameChange = 4,
	ChannelIconChange = 5,
	ChannelPinnedMessage = 6,
	UserJoin = 7,
	GuildBoost = 8,
	ThreadCreated = 18,
	Reply = 19,
	ChatInputCommand = 20,
	ThreadStarterMessage = 21,
	ContextMenuCommand = 23,
	AutoModerationAction = 24,
	PollResult = 46,
})

enums.TimestampStyle = table.freeze({
	ShortTime = "t", -- 16:20
	LongTime = "T", -- 16:20:30
	ShortDate = "d", -- 20/04/2021
	LongDate = "D", -- 20 April 2021
	ShortDateTime = "f", -- 20 April 2021 16:20
	LongDateTime = "F", -- Tuesday, 20 April 2021 16:20
	Relative = "R", -- 2 months ago
})

-- looks up `value` in one of the tables above case-insensitively, so builders can take "primary"
-- as well as 1. Numbers pass through. Errors on unknown names.
function enums.resolve(group: { [string]: any }, value: any, what: string?): any
	if value == nil or type(value) == "number" then
		return value
	end
	local wanted = string.lower(tostring(value))
	for name, v in group do
		if string.lower(name) == wanted then
			return v
		end
	end
	error(`unknown {what or "value"} "{value}"`, 3)
end

return table.freeze(enums)
