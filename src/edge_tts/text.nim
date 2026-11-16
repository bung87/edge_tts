import std/[re, strutils]
import ./[constants, formats, types]

proc removeIncompatibleCharacters*(text: string): string =
  result = text
  for ch in result.mitems:
    let code = ord(ch)
    if code <= 8 or code in 11..12 or code in 14..31:
      ch = ' '

proc escapeXml*(text: string): string =
  result = newStringOfCap(text.len)
  for ch in text:
    case ch
    of '&': result.add("&amp;")
    of '<': result.add("&lt;")
    of '>': result.add("&gt;")
    else: result.add(ch)

proc unescapeXml*(text: string): string =
  text.replace("&lt;", "<").replace("&gt;", ">")
    .replace("&quot;", "\"").replace("&apos;", "'").replace("&amp;", "&")

proc normalizeVoice*(voice: string): string =
  if voice.match(re"^Microsoft Server Speech Text to Speech Voice \(.+,.+\)$"):
    return voice

  var matches: array[3, string]
  if not voice.match(re"^([a-z]{2,})-([A-Z]{2,})-(.+Neural)$", matches):
    raise newException(ConfigurationError, "Invalid voice '" & voice & "'")

  var language = matches[0]
  var region = matches[1]
  var name = matches[2]
  let separator = name.find('-')
  if separator >= 0:
    region &= "-" & name[0 ..< separator]
    name = name[separator + 1 .. ^1]
  "Microsoft Server Speech Text to Speech Voice (" & language & "-" & region &
    ", " & name & ")"

proc validateConfig*(config: TtsConfig): TtsConfig =
  result = config
  result.voice = normalizeVoice(config.voice)
  result.outputFormat = if config.outputFormat.len == 0: DefaultOutputFormat
                        else: config.outputFormat
  discard getOutputFormat(result.outputFormat)
  if not config.rate.match(re"^[+-][0-9]+%$"):
    raise newException(ConfigurationError, "Invalid rate '" & config.rate & "'")
  if not config.volume.match(re"^[+-][0-9]+%$"):
    raise newException(ConfigurationError, "Invalid volume '" & config.volume & "'")
  if not config.pitch.match(re"^[+-][0-9]+Hz$"):
    raise newException(ConfigurationError, "Invalid pitch '" & config.pitch & "'")

func isContinuation(ch: char): bool =
  (ord(ch) and 0xC0) == 0x80

proc safeUtf8Split(text: string, proposed: int): int =
  result = proposed
  while result > 0 and result < text.len and isContinuation(text[result]):
    dec(result)

proc adjustEntitySplit(text: string, proposed: int): int =
  result = proposed
  while result > 0:
    let ampersand = text.rfind('&', 0, result - 1)
    if ampersand < 0:
      break
    if text.find(';', ampersand, result - 1) >= 0:
      break
    result = ampersand

proc splitTextByByteLength*(text: string, byteLength = MaxTextBytes): seq[string] =
  if byteLength <= 0:
    raise newException(ConfigurationError, "byteLength must be greater than zero")

  var remaining = text
  while remaining.len > byteLength:
    var splitAt = -1
    for i in 0 ..< byteLength:
      if remaining[i] in {'\n', ' '}:
        splitAt = i + 1
    if splitAt < 0:
      splitAt = safeUtf8Split(remaining, byteLength)
    else:
      splitAt = safeUtf8Split(remaining, splitAt)

    let originalSplit = splitAt
    splitAt = adjustEntitySplit(remaining, splitAt)
    if splitAt <= 0:
      if originalSplit > 0:
        splitAt = originalSplit
      else:
        raise newException(ConfigurationError,
          "byteLength is too small for a UTF-8 character or XML entity")

    let chunk = remaining[0 ..< splitAt].strip()
    if chunk.len > 0:
      result.add(chunk)
    remaining = remaining[splitAt .. ^1]

  let chunk = remaining.strip()
  if chunk.len > 0:
    result.add(chunk)
