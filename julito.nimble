# Package

version       = "0.1.0"
author        = "Guilherme Leoi"
description   = "Discord Bot that plays songs on voice chat, acting as an interface to yt-dlp"
license       = "GPL-3.0-only"
srcDir        = "src"
binDir        = "bin"
bin           = @["julito"]


# Dependencies

requires "nim >= 1.6.0"
requires "dimscord#head"
requires "dimscmd#head"
requires "dotenv >= 2.0.0"
requires "puppy >= 2.0.0"
