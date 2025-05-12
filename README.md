# RbxWebhook
A simple Discord Webhook module for Roblox.

## Features
- Built-in function documentation and auto-completion.
- Built-in method to get user thumbnail URLs.
- Checks to catch some malformed data early.
- Automatic color conversion to Discord's decimal format.
- Automatic DateTime object and Unix timestamp conversion to ISO-8601 for timestamps.
- Auto-retrying and option to add proxies.

## Installation
- Download the [latest release](../../releases/latest) and insert the lua file into your desired path.

## Documentation
### GetUserThumbnailAsync <samp>[string][string]</samp>
**`Yields`**

Gets the image URL of a user thumbnail.

#### Parameters
| Parameter | Description |
| - | - |
| userId: <samp>[int64][int64]</samp> | The UserId of the user to get the thumbnail of. |
| thumbnailType: <samp>[string][string]?</samp> | The type of user thumbnail to get.<br>**Possible Values: "avatar-headshot" \| "avatar-bust" \| "avatar"**<br>**Default Value: "avatar"** |
| thumbnailSize: <samp>[string][string]?</samp> | The size of the user thumbnail to get.<br>**Possible Values: "48x48" \| "50x50" \| "60x60" \| "75x75" \| "100x100" \| "110x110" \| "150x150" \| "180x180" \| "352x352" \| "420x420" \| "720x720"**<br>**Default Value: "48x48"** |
| thumbnailFormat: <samp>[string][string]?</samp> | The image format of the user thumbnail to get.<br>**Possible Values: "Png" \| "Jpeg" \| "Webp"**<br>**Default Value: "Png"** |
| isCircular: <samp>[boolean][bool]?</samp> | Determines whether the thumbnail should have rounded corners.<br>**Default Value: false** |<br>

#### Returns
| Type | Description |
| - | - |
| <samp>[string][string]</samp> | The image URL of the thumbnail. |

<br>

### SendMessageAsync <samp>[boolean][bool]</samp>, <samp>[Dictionary][dict]</samp> \| <samp>[string][string]</samp>
**`Yields`**

Sends `data` to the Discord Webhook with the given `webhookUrl`.<br>
Returns a `boolean` indicating the operation's success, and the request response or a `string` indicating the failure reason.

When `true`, the `ratelimitAutoRetry` parameter controls whether to retry sending automatically when rate limited by Discord *(must have sufficient proxies/attempts remaining to do so)*.

> [!WARNING]
This method does not apply global rate limiting, avoid sending requests from multiple threads simultaneously.

#### Parameters
| Parameter | Description |
| - | - |
| webhookUrl: <samp>[string][string]</samp> | The URL of the Discord Webhook to send the message to. |
| data: <samp>[Dictionary][dict]</samp> | The dictionary of data to send.<br>*(Auto-complete is available for this parameter)*<br>**See https://discord.com/developers/docs/resources/webhook#execute-webhook for more info** |
| ratelimitAutoRetry: <samp>[boolean][bool]</samp> | Controls whether to retry automatically when rate limited by Discord.<br>**Default Value: false** |

#### Returns
| Type | Description |
| - | - |
| <samp>[boolean][bool]</samp> | Whether the operation was successful. |
| <samp>[Dictionary][dict]</samp> \| <samp>[string][string] | The response of the request if the operation was successful, or the failure reason string if it was not. |

<br>

### Code Samples
This code sample demonstrates sending a message with a username and avatar image override, a message reading "Hello World!", an embed, a poll with 2 answers lasting 12 hours, and other miscellaneous options.
```lua
local discordWebhook = require(PATH_TO_MODULE)

local data: discordWebhook.webhookData = {
	-- Override the webhook profile
	["username"] = "RbxWebhook",
	["avatar_url"] = discordWebhook.GetUserThumbnailAsync(1, "avatar-headshot", "100x100"),
	
	-- Content
	["content"] = "Hello World!",
	["embeds"] = {},
	["poll"] = {
		["question"] = {["text"] = "Is this a poll?"},
		["answers"] = {
			{
				["poll_media"] = {
					["emoji"] = {["name"] = "✅"},
					["text"] = "Yes"
				}
			},
			{
				["poll_media"] = {
					["emoji"] = {["name"] = "❌"},
					["text"] = "No"
				}
			}
		},
		["duration"] = 12 -- Run the poll for 12 hours
	},
	
	-- Miscellaneous
	["tts"] = true, -- Speak the message
	["allowed_mentions"] = {
		["parse"] = {} -- Ping no one!
	},
	["flags"] = {"SUPPRESS_NOTIFICATIONS"} -- Send as an @silent message
}

-- Embeds
data.embeds[1] = {
	["title"] = "Title",
	["description"] = "Description",
	["fields"] = {},
	["footer"] = {["text"] = "Footer"},
	["timestamp"] = DateTime.now(),
	["color"] = Color3.new(0.6,0.2,1),
	["url"] = "https://google.com",
	["author"] = {
		["name"] = "Author Name",
		["url"] = "https://example.com"
	}
}
local embed1 = data.embeds[1]
embed1.fields[1] = {
	["name"] = "Field 1",
	["value"] = "Value",
	["inline"] = true
}
embed1.fields[2] = {
	["name"] = "Field 2",
	["value"] = "Value",
	["inline"] = true
}
embed1.fields[3] = {
	["name"] = "Field 3",
	["value"] = "Value"
}

local success, response = discordWebhook.SendMessageAsync("WEBHOOK_URL", data, true)

if success then
	print("Sent successfully!")
else
	warn("Failed to send:", response)
end
```

[int64]: https://create.roblox.com/docs/luau/numbers#int64
[string]: https://create.roblox.com/docs/luau/strings
[bool]: https://create.roblox.com/docs/luau/booleans
[dict]: https://create.roblox.com/docs/luau/tables#dictionaries
