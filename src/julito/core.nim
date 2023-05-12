import std/[re, asyncdispatch, tables, options, strformat, strutils, os, osproc]
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

  const
    TimeoutMs = 5000
    StepMs = 10
  var elapsedMs = 0
  while elapsedMs < TimeoutMs and not voiceSessionReady[guildId]:
    await sleepAsync StepMs
    elapsedMs += StepMs
  if elapsedMs >= TimeoutMs:
    raise newException(ResourceExhaustedError, "Timeout for voice connection reached")

proc playYouTubeContent(vc: VoiceClient, playbackUrl: string) {.async.} =
  const Command = "yt-dlp"
  if findExe(Command) == "":
    raise newException(OSError, fmt"Couldn't find `{Command}` in PATH (is it installed?)")

  let 
    output =
      execProcess(
        Command,
        args = ["--get-url", playbackUrl],
        options = {poUsePath,
        poStdErrToStdOut}
      )
    first = output.split("\n")[0]
    sec = output.split("\n")[1]
  
  if not first.startsWith("http") and not sec.startsWith("http"):
      raise newException(ValueError, "Error occurred: " & output)

  if not sec.startsWith("http"): 
      await vc.playFFMPEG(first)
  else:
      await vc.playFFMPEG(sec)

proc tryToPlay*(vc: VoiceClient; guildId, playbackUrl: string) {.async.} =
  try:
    currentPlaybackUrl[guildId] = playbackUrl
    await vc.playYouTubeContent(playbackUrl)
  except ValueError, IOError:
    currentPlaybackUrl[guildId] = ""
    echo fmt"Invalid URL {playbackUrl}"
  
proc readyVoiceSession*(guildId: string) =
  voiceSessionReady[guildId] = true

proc unreadyVoiceSession*(guildId: string) =
  voiceSessionReady[guildId] = false

proc isVoiceSessionReady*(guildId: string): bool =
  voiceSessionReady[guildId]