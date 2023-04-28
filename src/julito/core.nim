import std/[re, asyncdispatch, tables, options]
import dimscord
import puppy

var
  voiceSessionReady: Table[string, bool]
  currentPlaybackUrl*: Table[string, string]

proc pickPetitVideoCode*(): string =
  result = "wDgQdr8ZkTw"
  let
    pattern = re"https:\/\/(?:www\.|)youtube\.com\/(?:[a-z]+)\/([^\?\/]+)"
    petit = fetch("https://petittube.com/")
  var youtubeMatches: array[8, string]
  if petit.find(pattern, youtubeMatches) >= 0:
    return youtubeMatches[0]

proc connectToVoiceChannel*(s: Shard; voiceChannelId: Option[string]; guildId: string) {.async.} =
  if guildId notin s.voiceConnections:
    await s.voiceStateUpdate(
      guildId = guildId,
      channelId = voiceChannelId,
      selfDeaf = true
    )
    voiceSessionReady[guildId] = false

  while not voiceSessionReady[guildId]:
    await sleepAsync 10
  
proc readyVoiceSession*(guildId: string) =
  voiceSessionReady[guildId] = true

proc unreadyVoiceSession*(guildId: string) =
  voiceSessionReady[guildId] = false

proc isVoiceSessionReady*(guildId: string): bool =
  voiceSessionReady[guildId]