import julito/core
import std/[asyncdispatch, options, strutils, strformat, tables, os, re]
import dimscord, dimscmd
import dotenv

const
  isDebugBuild = not (defined(release) or defined(danger))
  DefaultGuildId = when isDebugBuild: "1067590610816602172" else: ""

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
      vc.stopped = true
      v.loops = 0
      v.start = 0.0
      if playbackQueue.getOrDefault(g.id).len == 0:
        echo "Deleting queue..."
        playbackQueue.del(g.id)
      else:
        echo "Playing next video in queue..."
        while currentPlaybackUrl.getOrDefault(g.id) == "" and playbackQueue.getOrDefault(g.id).len > 0:
          let playbackUrl = playbackQueue[g.id][0]
          playbackQueue[g.id].delete(0)
          echo fmt"Trying to play {playbackUrl}"
          await vc.tryToPlay(g.id, playbackUrl)
  echo "Starting session"
  await vc.startSession()


cmd.addSlash("connect", guildId = DefaultGuildId) do ():
  ## Enters the voice channel you're connected to without adding to queue
  let g = s.cache.guilds[i.guildId.get]
  echo "In the command `connect`"
  if i.member.get.user.id notin g.voiceStates:
    await discord.api.interactionResponseMessage(i.id, i.token,
      kind = irtChannelMessageWithSource,
      response = InteractionCallbackDataMessage(
        content: "You're not connected to a voice channel.",
        flags: { mfEphemeral }
      )
    )
    return
  let
    voiceChannelId = g.voiceStates[i.member.get.user.id].channelId
    connecting = fmt"Connecting to <#{voiceChannelId.get}>..."
  await discord.api.interactionResponseMessage(i.id, i.token,
    kind = irtChannelMessageWithSource,
    response = InteractionCallbackDataMessage(
      content: ""
    )
  )
  await s.connectToVoiceChannel(voiceChannelId, i.guildId.get)
  
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
  let
    playbackUrl =
      if url.match(re"https:\/\/(?:www\.|)youtu\.be\/([^\?\/]+)") or
         url.match(re"https:\/\/(?:www\.|)youtube\.com\/watch\?v=([^\?\/]+)") or
         url.match(re"https:\/\/(?:www\.|)youtube\.com\/(?:[a-z]+)\/([^\?\/]+)"):
        url
      else:
        fmt"https://youtu.be/{pickPetitVideoCode()}"
    voiceChannelId = g.voiceStates[i.member.get.user.id].channelId
  if i.guildId.get in currentPlaybackUrl and currentPlaybackUrl[i.guildId.get] != "":
    if not playbackQueue.hasKey(i.guildId.get):
      playbackQueue[i.guildId.get] = @[]
    let
      queuePos = playbackQueue[i.guildId.get].len + 2
      queueing = fmt"{playbackUrl} was added to queue! (Position: {queuePos})"
    playbackQueue[i.guildId.get].add(playbackUrl)
    await discord.api.interactionResponseMessage(i.id, i.token,
      kind = irtChannelMessageWithSource,
      response = InteractionCallbackDataMessage(
        content: queueing
      )
    )
    echo queueing
    await s.connectToVoiceChannel(voiceChannelId, i.guildId.get)
    return
  let playing = fmt"Playing {playbackUrl} at <#{voiceChannelId.get}>!"
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
