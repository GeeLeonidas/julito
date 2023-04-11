import std/[re]
import puppy

proc pickPetitVideoCode*(): string =
  result = "wDgQdr8ZkTw"
  let
    pattern = re"https:\/\/(?:www\.|)youtube\.com\/(?:[a-z]+)\/([^\?\/]+)"
    petit = fetch("https://petittube.com/")
  var youtubeMatches: array[8, string]
  if petit.find(pattern, youtubeMatches) >= 0:
    return youtubeMatches[0]