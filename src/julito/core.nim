import std/[re, asyncdispatch, tables, options, strformat]
import dimscord, dimscord/voice
import puppy

var
  voiceSessionReady: Table[string, bool]
  currentPlaybackUrl*: Table[string, string]
  playbackQueue*: Table[string, seq[string]]

proc pickPetitVideoCode*(): string =
  result = "wDgQdr8ZkTw"
  try:
    let
      pattern = re"https:\/\/(?:www\.|)youtube\.com\/(?:[a-z]+)\/([^\?\/]+)"
      petit = fetch("https://petittube.com/")
    var youtubeMatches: array[8, string]
    if petit.find(pattern, youtubeMatches) >= 0:
      return youtubeMatches[0]
  except PuppyError:
    echo "Error fetching Petit Tube"

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

proc tryToPlay*(vc: VoiceClient; guildId, playbackUrl: string) {.async.} =
  try:
    currentPlaybackUrl[guildId] = playbackUrl
    await vc.playYTDL(playbackUrl, "yt-dlp")
  except:
    currentPlaybackUrl[guildId] = ""
    echo fmt"Invalid URL {playbackUrl}"
  
proc readyVoiceSession*(guildId: string) =
  voiceSessionReady[guildId] = true

proc unreadyVoiceSession*(guildId: string) =
  voiceSessionReady[guildId] = false

proc isVoiceSessionReady*(guildId: string): bool =
  voiceSessionReady[guildId]