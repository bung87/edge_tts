import std/[os, strutils]
import chronos
import edge_tts

proc main() {.async.} =
  let localeFilter = if paramCount() >= 1: paramStr(1).toLowerAscii() else: ""
  let voices = await listVoices()
  for voice in voices:
    if localeFilter.len == 0 or voice.locale.toLowerAscii().startsWith(localeFilter):
      echo voice.shortName, " | ", voice.gender, " | ", voice.friendlyName

waitFor(main())
