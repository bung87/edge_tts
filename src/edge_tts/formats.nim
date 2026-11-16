import std/strutils
import ./types

type
  OutputFormatInfo* = object
    name*: string
    contentType*: string
    extension*: string
    bytesPerSecond*: int64 ## Zero selects metadata-based offset compensation.

func mp3(bitrateKbps: int): OutputFormatInfo =
  OutputFormatInfo(
    name: "audio-24khz-" & $bitrateKbps & "kbitrate-mono-mp3",
    contentType: "audio/mpeg", extension: ".mp3",
    bytesPerSecond: bitrateKbps * 125)

const AvailableOutputFormats = [
  mp3(48),
  mp3(96),
  OutputFormatInfo(
    name: "webm-24khz-16bit-mono-opus",
    contentType: "audio/webm", extension: ".webm")
]

proc outputFormats*(): seq[OutputFormatInfo] =
  @AvailableOutputFormats

proc getOutputFormat*(name: string): OutputFormatInfo =
  for format in AvailableOutputFormats:
    if format.name == name:
      return format
  raise newException(ConfigurationError, "Unsupported output format '" & name & "'")

proc acceptsContentType*(format: OutputFormatInfo, actual: string): bool =
  let contentType = actual.toLowerAscii().split(';', 1)[0].strip()
  contentType == format.contentType or contentType == "application/octet-stream"
