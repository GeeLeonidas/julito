import julito/core
import std/[asyncdispatch, options, strutils, strformat, tables, os, re]
import dimscord, dimscmd
import dotenv

if os.fileExists(".env"):
  dotenv.load()
assert os.existsEnv("JULITO_TOKEN"), "Env variable `JULITO_TOKEN` is missing!"
let discord = newDiscordClient(os.getEnv("JULITO_TOKEN"))
var cmd = discord.newHandler()

proc onReady(s: Shard, r: Ready) {.event(discord).} =
  await cmd.registerCommands()
  echo r.user, " is ready!"

proc interactionCreate(s: Shard, i: Interaction) {.event(discord).} =
  discard await cmd.handleInteraction(s, i)

proc voiceServerUpdate(s: Shard, g: Guild, token: string;
  endpoint: Option[string]; initial: bool) {.event(discord).} =
  let vc = s.voiceConnections[g.id]

  vc.voiceEvents.onReady = proc (v: VoiceClient) {.async.} =
    readyVoiceSession(g.id)

  vc.voiceEvents.onSpeaking = proc (v: VoiceClient, s: bool) {.async.} =
    if not s and v.sent == 0:
      echo "Playback ended"
      currentPlaybackUrl.del(g.id)

  echo "Starting session"
  await vc.startSession()


const DefaultGuildId = when defined(debug): "1067590610816602172" else: ""

cmd.addSlash("play", guildId = DefaultGuildId) do (url: string):
  ## Plays given youtube content at the voice channel you're connected to
  let g = s.cache.guilds[i.guildId.get]
  echo "In the command `play`"
  if i.member.get.user.id notin g.voiceStates:
    await discord.api.interactionResponseMessage(i.id, i.token,
      kind = irtChannelMessageWithSource,
      response = InteractionCallbackDataMessage(
        content: "You're not connected to a voice channel.",
        flags: { mfEphemeral }
      )
    )
    return
  if i.guildId.get in currentPlaybackUrl and currentPlaybackUrl[i.guildId.get] != "":
    await discord.api.interactionResponseMessage(i.id, i.token,
      kind = irtChannelMessageWithSource,
      response = InteractionCallbackDataMessage(
        content: "This bot currently doesn't support queues.",
        flags: { mfEphemeral }
      )
    )
    return
  let
    playbackUrl =
      if url.match(re"https:\/\/(?:www\.|)youtu\.be\/([^\?\/]+)") or
         url.match(re"https:\/\/(?:www\.|)youtube\.com\/watch\?v=([^\?\/]+)") or
         url.match(re"https:\/\/(?:www\.|)youtube\.com\/(?:[a-z]+)\/([^\?\/]+)"):
        url
      else:
        fmt"https://youtu.be/{pickPetitVideoCode()}"
    playing = fmt"Playing {playbackUrl}"
  await discord.api.interactionResponseMessage(i.id, i.token,
    kind = irtChannelMessageWithSource,
    response = InteractionCallbackDataMessage(
      content: playing
    )
  )
  await s.connectToVoiceChannel(g.voiceStates[i.member.get.user.id].channelId, i.guildId.get)

  let vc = s.voiceConnections[i.guildId.get]
  echo playing
  try:
    currentPlaybackUrl[i.guildId.get] = playbackUrl
    await vc.playYTDL(playbackUrl, "yt-dlp")
  except:
    currentPlaybackUrl[i.guildId.get] = ""
    echo fmt"Invalid URL {playbackUrl}"

cmd.addSlash("stop", guildId = DefaultGuildId) do ():
  ## Stops current playback and disconnects from voice
  if i.guildId.get notin s.voiceConnections:
    await discord.api.interactionResponseMessage(i.id, i.token,
      kind = irtChannelMessageWithSource,
      response = InteractionCallbackDataMessage(
        content: fmt"{s.user.username} is already disconnected.",
        flags: { mfEphemeral }
      )
    )
    return
  let vc = s.voiceConnections[i.guildId.get]
  if not vc.ready:
    await discord.api.interactionResponseMessage(i.id, i.token,
      kind = irtChannelMessageWithSource,
      response = InteractionCallbackDataMessage(
        content: fmt"Whoah! Slow down buddy!",
        flags: { mfEphemeral }
      )
    )
    return

  let stopping = "Stopping playback and disconnecting..."
  await discord.api.interactionResponseMessage(i.id, i.token,
    kind = irtChannelMessageWithSource,
    response = InteractionCallbackDataMessage(
      content: stopping
    )
  )
  echo stopping

  vc.stopped = true
  unreadyVoiceSession(i.guildId.get)
  await s.voiceStateUpdate( # if channelID is none then we would disconnect
      guildID = i.guildId.get,
      channelId = none string
  )


waitFor discord.startSession(
  gatewayIntents = {
    giGuilds,
    giGuildVoiceStates
  }
)
