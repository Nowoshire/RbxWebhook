--[[
A Discord Webhook module.

Features:
- Built-in function documentation and auto-completion.
- Built-in method to get user thumbnail URLs.
- Checks to catch most malformed data early.
- Automatic color conversion to Discord's decimal format.
- Automatic DateTime object and Unix timestamp conversion to ISO8601 for timestamps.
- Proxies and fallbacks.

For more information see:
- https://discord.com/developers/docs/resources/webhook
]]

-- Configuration --
local CONFIG = {
	--[[ API Options ]]--
	-- How many times to try a proxy
	MaxAttemptsPerProxy = 2,

	-- Roblox API Proxies
	RobloxAPIProxyURLs = {
		"https://%s.roproxy.com%s"
	},

	-- Discord Webhook proxies, in case Roblox servers are blocked
	DiscordWebhookProxies = {
		"discord.com", -- Attempt discord.com, as webhooks are not blocked as of writing this script.
		--"webhook.lewisakura.moe"
	},

	FallbackUserThumbnailURL = "https://cdn.discordapp.com/embed/avatars/0.png",

	-- Output debug messages
	DebugMode = true
}

-- Discord Limits --
-- ! DO NOT CHANGE THESE UNLESS YOU KNOW WHAT YOU ARE DOING ! --
local DISCORD_LIMITS = {
	ContentMaxChars				= 2000,
	ProfileUsernameMaxChars		= 80,
	ForumThreadNameMaxChars		= 100,
	MessageMaxEmbeds			= 10,
	EmbedAuthorNameMaxChars		= 256,
	EmbedTitleMaxChars			= 256,
	EmbedDescriptionMaxChars	= 4096,
	EmbedMaxFields				= 25,
	EmbedFieldNameMaxChars		= 256,
	EmbedFieldValueMaxChars		= 1024,
	EmbedFooterTextMaxChars		= 2048,
	AllowedMentionsMaxRoles		= 100,
	AllowedMentionsMaxUsers		= 100,
	EmbedsMaxCharSum			= 6000,
	PollQuestionMaxChars		= 300,
	PollAnswerMaxChars			= 55
}

-- Services --
local HttpService = game:GetService("HttpService")
local TestService = game:GetService("TestService")

-- Types --
type thumbnailType = "avatar-headshot" | "avatar-bust" | "avatar"
type thumbnailSize = "48x48" | "50x50" | "60x60" | "75x75" | "100x100" | "110x110" | "150x150" | "180x180" | "352x352" | "420x420" | "720x720"
type thumbnailFormat = "Png" | "Jpeg" | "Webp"
type ISO8601 = DateTime | string | number
type bitfield = {("SUPPRESS_EMBEDS"?) & ("SUPPRESS_NOTIFICATIONS"?)} | typeof(buffer.create(2)) | number
type HttpRequestAsyncResponse = {
	Success: boolean,
	StatusCode: number,
	StatusMessage: string,
	Headers: {[string]: any},
	Body: string
}
export type webhookData = {
	username: string?,
	avatar_url: string?,
	content: string?,
	embeds: {{
		color: (Color3 | number)?,
		author: {
			name: string,
			url: string?,
			icon_url: string?
		}?,
		title: string?,
		url: string?,
		description: string?,
		fields: {{
			name: string,
			value: string,
			inline: boolean?
		}}?,
		thumbnail: {url: string}?,
		image: {url: string}?,
		footer: {
			text: string,
			icon_url: string?
		}?,
		timestamp: ISO8601?
	}?}?,
	poll: {
		question: {text: string},
		answers: {{
			poll_media: {
				text: string?,
				emoji: {
					id: number?,
					name: string?
				}?
			}
		}},
		duration: number?,
		allow_multiselect: boolean?
	}?,
	tts: boolean?,
	allowed_mentions: {
		parse: {("roles"?) & ("users"?) & ("everyone"?)}?,
		roles: {number}?,
		users: {number}?
	}?,
	flags: (bitfield)?,
	thread_name: string?,
	applied_tags: {number}?
}

-- Module --
local webhook = {}

-- Functions --
-- Private

local bitfieldFlags = {
	["SUPPRESS_EMBEDS"] = 2 ^ 2,
	["SUPPRESS_NOTIFICATIONS"] = 2 ^ 12,
}

--[[
Converts message flags to a bitfield int value
]]
local function messageFlagsToInt(bitfield: bitfield): number
	local bitfieldType = type(bitfield)
	if bitfieldType == "number" then
		return bitfield
	end

	if bitfieldType == "buffer" then
		if buffer.len(bitfield) ~= 2 then
			return 0
		end

		return buffer.readu16(bitfield, 0)
	end

	local bitInt = 0
	if bitfieldType == "table" then
		local seenFlags = {}

		for _, flag in bitfield do
			if table.find(seenFlags, flag) then continue end
			table.insert(seenFlags, flag)

			bitInt += bitfieldFlags[flag] or 0
		end
	end

	return bitInt
end

--[[
Converts a color value to Discord's decimal format.
]]
local function colorToDec(color: Color3 | number): number
	if type(color) == "number" then
		return color
	end

	return tonumber(color:ToHex(), 16)
end

--[[
Converts a date value to an ISO-8601 string.
]]
local function toISO8601String(a: ISO8601): string
	local aType = type(a)

	if aType == "string" then
		return a
	end

	if aType == "number" then
		a = DateTime.fromUnixTimestampMillis(a * 1000)
	end

	return a:ToIsoDate()
end

--[[
[YIELDS]
Sends a HTTP GET request to the provided Roblox API, attempting with each proxy in the list until it succeeds or there are no more proxies.
]]
local function RbxApiGetAsync(subdomain: string, path: string, nocache: boolean?, headers: {[string]: any}?): (boolean, string?)
	for _, proxy in ipairs(CONFIG.RobloxAPIProxyURLs) do
		for _ = 1, CONFIG.MaxAttemptsPerProxy do
			local url = string.format(proxy, subdomain, path)
			local success, result = pcall(HttpService.GetAsync, HttpService, url, nocache, headers)

			if success then
				return true, result
			end
		end
	end

	return false, nil
end

-- Public

--[[
[YIELDS]
Returns the image URL of a user thumbnail given the type, size, format and isCircular properties.
]]
function webhook.GetUserThumbnailAsync(
	userId: number,
	thumbnailType: thumbnailType?,
	thumbnailSize: thumbnailSize?,
	thumbnailFormat: thumbnailFormat?,
	isCircular: boolean?
): string

	local success, response = RbxApiGetAsync("thumbnails", `/v1/users/{thumbnailType or "avatar"}?userIds={userId}&size={thumbnailSize or "48x48"}&format={thumbnailFormat or "Png"}&isCircular={isCircular or false}`)

	-- Error Handling
	if not success then
		if CONFIG.DebugMode then
			warn(response)
		end

		return CONFIG.FallbackUserThumbnailURL
	end

	local decodedResponse: {data: {{targetId: number, state: string, imageUrl: string, version: string}}} = HttpService:JSONDecode(response)

	return decodedResponse.data[1].imageUrl
end

local cachedInvalidWebhooks: {string} = {}

--[[
[YIELDS]
Sends the provided data to the given Discord webhook.
Returns a boolean indicating the operation's success, a string with the Request response or request failure reason.

`ratelimitAutoRetry` determines whether to retry automatically when rate limited (HTTP 429).
]]
function webhook.SendMessageAsync(webhookUrl: string, data: webhookData, ratelimitAutoRetry: boolean?): (boolean, HttpRequestAsyncResponse | string)
	-- Validation
	if table.find(cachedInvalidWebhooks, webhookUrl) then
		return false, "invalid webhook url"
	end

	-- Check minimum requirements
	local content, embeds, poll = data.content, data.embeds, data.poll
	if not content and not data.embeds and not data.poll then
		return false, "missing required fields (one of content, embeds, or poll is required)"
	end

	-- Check content
	if content ~= nil then
		if type(content) ~= "string" then
			return false, "invalid content value type (expects string)"
		end
		if #content > DISCORD_LIMITS.ContentMaxChars then
			return false, "content too long"
		end
	end

	-- Check username (webhook profile name override)
	local username = data.username
	if username ~= nil then
		if type(username) ~= "string" then
			return false, "invalid username value type (expects string)"
		end

		if #username > DISCORD_LIMITS.ProfileUsernameMaxChars then
			return false, "username too long"
		end
	end

	-- Check avatar_url (webhook profile avatar override)
	local avatar_url = data.avatar_url
	if avatar_url ~= nil then
		if type(avatar_url) ~= "string" then
			return false, "invalid avatar_url value type (expects string)"
		end
	end

	-- Check tts
	local tts = data.tts
	if tts ~= nil and type(tts) ~= "boolean" then
		return false, "invalid tts value type (expects boolean)"
	end

	-- Check allowed_mentions
	local allowed_mentions = data.allowed_mentions
	if allowed_mentions ~= nil then
		if type(allowed_mentions) ~= "table" then
			return false, "invalid allowed_mentions value type (expects dictionary)"
		end

		-- Check parse
		local parse = allowed_mentions.parse
		if parse ~= nil then
			if type(parse) ~= "table" then
				return false, "invalid allowed_mentions.parse value type (expects array)"
			end
		end

		-- Check users
		local users = allowed_mentions.users
		if users ~= nil then
			if type(users) ~= "table" then
				return false, "invalid allowed_mentions.users value type (expects array)"
			end

			-- Check num users
			local numUsers = #users
			if #numUsers > DISCORD_LIMITS.AllowedMentionsMaxUsers then
				return false, "too many allowed_mentions.users snowflakes"
			end

			-- Check mutual exclusivity
			if numUsers ~= 0 and parse and table.find(parse, "users") then
				return false, "allowed_mentions.users cannot be set when \"users\" is present in allowed_mentions.parse"
			end
		end

		-- Check roles
		local roles = allowed_mentions.roles
		if roles ~= nil then
			if type(roles) ~= "table" then
				return false, "invalid allowed_mentions.roles value type (expects array)"
			end

			if #roles > DISCORD_LIMITS.AllowedMentionsMaxRoles then
				return false, "too many allowed_mentions.roles snowflakes"
			end
		end
	end

	-- Check message flags
	local flags = data.flags
	if flags ~= nil then
		flags = messageFlagsToInt(flags)

		if flags ~= 0 and flags ~= 4 and flags ~= 4096 and flags ~= 4100 then
			return false, "invalid message flags"
		end

		data.flags = flags
	end

	-- Check thread_name
	local thread_name = data.thread_name
	if thread_name ~= nil then
		if type(thread_name) ~= "string" then
			return false, "invalid thread_name value type (expects string)"
		end

		if #thread_name > DISCORD_LIMITS.ForumThreadNameMaxChars then
			return false, "thread_name too long"
		end
	end

	-- Check embeds
	if embeds ~= nil then
		local embedCharSum = 0

		-- Embed count limit
		if #embeds > DISCORD_LIMITS.MessageMaxEmbeds then
			return false, "too many embeds"
		end

		for _, embed in embeds do
			-- Check title
			local title = embed.title
			if title ~= nil then
				if type(title) ~= "string" then
					return false, "invalid embed.title value type (expects string)"
				end

				local titleLen = #title
				if titleLen > DISCORD_LIMITS.EmbedTitleMaxChars then
					return false, "embed.title too long"
				end

				embedCharSum += titleLen
			end

			-- Check description
			local description = embed.description
			if description ~= nil then
				if type(description) ~= "string" then
					return false, "invalid embed.description value type (expects string)"
				end

				local descriptionLen = #description
				if descriptionLen > DISCORD_LIMITS.EmbedDescriptionMaxChars then
					return false, "embed.description too long"
				end

				embedCharSum += descriptionLen
			end

			-- Check color
			local color = embed.color
			if color ~= nil then
				local colorType = typeof(color)
				if colorType ~= "number" and colorType ~= "Color3" then
					return false, "invalid embed.color value type (expects Color3 or number)"
				end

				embed.color = colorToDec(color)
			end

			-- Check timestamp
			local timestamp = embed.timestamp
			if timestamp ~= nil then
				local timestampType = typeof(timestamp)
				if timestampType ~= "DateTime" and timestampType ~= "string" and timestampType ~= "number" then
					return false, "invalid embed.timestamp value type (expects DateTime, number, or string)"
				end

				embed.timestamp = toISO8601String(timestamp)
			end

			-- Check URL
			local url = embed.url
			if url ~= nil and type(url) ~= "string" then
				return false, "invalid embed.url value type (expects string)"
			end

			-- Check footer
			local footer = embed.footer
			if footer ~= nil then
				if type(footer) ~= "table" then
					return false, "invalid embed.footer value type (expects dictionary)"
				end

				local text = footer.text
				if text ~= nil then
					if type(text) ~= "string" then
						return false, "invalid footer.text value type (expects string)"
					end

					local textLen = #text
					if textLen > DISCORD_LIMITS.EmbedFooterTextMaxChars then
						return false, "footer.text too long"
					end

					embedCharSum += textLen
				end

				if footer.icon_url ~= nil and type(footer.icon_url) ~= "string" then
					return false, "invalid footer.icon_url value type (expects string)"
				end
			end

			-- Check image
			local image = embed.image
			if image ~= nil then
				if type(image) ~= "table" then
					return false, "invalid embed.image value type (expects dictionary)"
				end

				if type(image.url) ~= "string" then
					return false, "invalid image.url value type (expects string)"
				end
			end

			-- Check thumbnail
			local thumbnail = embed.thumbnail
			if thumbnail ~= nil then
				if type(thumbnail) ~= "table" then
					return false, "invalid embed.thumbnail value type (expects dictionary)"
				end

				if type(thumbnail.url) ~= "string" then
					return false, "invalid thumbnail.url value type (expects string)"
				end
			end

			-- Check author
			local author = embed.author
			if author ~= nil then
				if type(author) ~= "table" then
					return false, "invalid embed.author value type (expects dictionary)"
				end

				local name = author.name
				if type(name) ~= "string" then
					return false, "invalid author.name value type (expects string)"
				end

				local nameLen = #name
				if nameLen > DISCORD_LIMITS.EmbedAuthorNameMaxChars then
					return false, "author.name too long"
				end

				embedCharSum += nameLen

				local url = author.url
				if url ~= nil and type(url) ~= "string" then
					return false, "invalid author.url value type (expects string)"
				end

				local icon_url = author.icon_url
				if icon_url ~= nil and type(icon_url) ~= "string" then
					return false, "invalid author.icon_url value type (expects string)"
				end
			end

			-- Check fields
			local fields = embed.fields
			if fields ~= nil then
				if type(fields) ~= "table" then
					return false, "invalid embed.fields value type (expects array)"
				end

				-- Field count limit
				if #fields > DISCORD_LIMITS.EmbedMaxFields then
					return false, "too many embed.fields fields"
				end

				for _, field in fields do
					local name = field.name
					if type(name) ~= "string" then
						return false, "invalid field.name value type (expects string)"
					end

					local nameLen = #name
					if nameLen > DISCORD_LIMITS.EmbedFieldNameMaxChars then
						return false, "field.name too long"
					end

					local value = field.value
					if type(value) ~= "string" then
						return false, "invalid field.value value type (expects string)"
					end

					local valueLen = #value
					if valueLen > DISCORD_LIMITS.EmbedFieldValueMaxChars then
						return false, "field.value too long"
					end

					local inline = field.inline
					if inline ~= nil then
						if type(inline) ~= "boolean" then
							return false, "invalid field.inline value type (expects boolean)"
						end
					end

					embedCharSum += nameLen + valueLen
				end
			end
		end

		-- Check character sum
		if embedCharSum > DISCORD_LIMITS.EmbedsMaxCharSum then
			return false, "embeds too large"
		end
	end

	-- Check poll
	local poll = data.poll
	if poll ~= nil then
		if type(poll) ~= "table" then
			return false, "invalid poll value type (expects dictionary)"
		end

		-- Check duration
		local duration = poll.duration
		if duration ~= nil then
			if type(duration) ~= "number" then
				return false, "invalid poll.duration value type (expects number)"
			end

			poll.duration = math.clamp(math.round(poll.duration), 0, 768)
		end

		-- Check question
		local question = poll.question
		if type(question) ~= "table" then
			return false, "invalid poll.question value type (expects dictionary)"
		end

		local questionText = question.text
		if type(questionText) ~= "string" then
			return false, "invalid question.text value type (expects string)"
		end

		local qTextLen = #questionText
		if qTextLen == 0 then
			return false, "question.text cannot be empty"
		end
		if qTextLen > DISCORD_LIMITS.PollQuestionMaxChars then
			return false, "question.text too long"
		end

		-- Check answers
		local answers = poll.answers
		if type(answers) ~= "table" then
			return false, "invalid poll.answers value type (expects array)"
		end
	end

	-- Sending
	local jsonData = HttpService:JSONEncode(data)

	for proxyNum, proxy in ipairs(CONFIG.DiscordWebhookProxies) do
		local url = string.gsub(webhookUrl, "discord.com", proxy, 1)

		for attempt = 1, CONFIG.MaxAttemptsPerProxy do
			local callSuccess, response: HttpRequestAsyncResponse = pcall(HttpService.RequestAsync, HttpService, {
				Url = url,
				Method = "POST",
				Body = jsonData,
				Headers = {
					["Content-Type"] = "application/json"
				}
			})

			-- RequestAsync threw an error
			if not callSuccess then
				if CONFIG.DebugMode then
					TestService:Error(response, script, nil)
				end
				continue -- Try again
			end

			-- Success
			if response.Success then
				if CONFIG.DebugMode then
					TestService:Message(`Successfully sent Webhook message. (HTTP Status: {response.StatusCode}: {response.StatusMessage})`, nil, nil)
				end

				return true, response
			end

			-- Error Handling

			-- 400: Bad request (malformed data)
			if response.StatusCode == 400 then
				if CONFIG.DebugMode then
					TestService:Error(`HTTP 400: {response.StatusMessage}:\n{response.Body}`, script, nil)
				end

				return false, response
			end

			-- 401/404: Unauthorized/Invalid Webhook
			if response.StatusCode == 401 or response.StatusCode == 404 then
				table.insert(cachedInvalidWebhooks, webhookUrl)

				if CONFIG.DebugMode then
					TestService:Error(`HTTP {response.StatusCode}: {response.StatusMessage}\n{response.Body}`, script, nil)
				end

				return false, response
			end

			-- 429: Rate limited
			if response.StatusCode == 429 then
				if CONFIG.DebugMode then
					TestService:Error(`HTTP 429: {response.StatusMessage}\n{response.Body}`, script, nil)
				end

				if ratelimitAutoRetry and (attempt ~= CONFIG.MaxAttemptsPerProxy or CONFIG.DiscordWebhookProxies[proxyNum + 1]) then
					local retryAfter: number = HttpService:JSONDecode(response.Body).retry_after or 1

					if CONFIG.DebugMode then
						TestService:Message(`Auto-retry is enabled and available, retrying after {retryAfter + 0.2}s.`, script, nil)
					end

					task.wait(retryAfter)

					continue
				else
					return false, response
				end
			end
		end
	end

	if CONFIG.DebugMode then
		TestService:Error("Failed to send: exhausted proxies/attempts", script, nil)
	end

	return false, "failed to send: exhausted attempts"
end

return table.freeze(webhook)