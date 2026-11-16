import std/[json, strutils, unittest]
import edge_tts/[protocol, text, types]

proc binaryMessage(header: string, payload: openArray[byte] = []): seq[byte] =
  let length = header.len + 2
  result = @[byte(length shr 8), byte(length)]
  for ch in header:
    result.add(byte(ch))
  result.add([13'u8, 10'u8])
  result.add(payload)

suite "Edge protocol":
  let config = validateConfig(TtsConfig(voice: "en-US-EmmaMultilingualNeural",
    rate: "+0%", volume: "+0%", pitch: "+0Hz"))

  test "speech config request":
    let request = speechConfigRequest(config)
    check request.contains("Path:speech.config")
    check request.contains("\"sentenceBoundaryEnabled\":\"true\"")
    check request.contains("\"wordBoundaryEnabled\":\"false\"")
    let body = request.split("\r\n\r\n", 1)[1]
    let parsed = parseJson(body)
    check parsed["context"]["synthesis"]["audio"]["outputFormat"].getStr() ==
      "audio-24khz-48kbitrate-mono-mp3"

  test "SSML request":
    let request = ssmlRequest("abc", "timestamp", config, "A &amp; B")
    check request.startsWith("X-RequestId:abc\r\n")
    check request.contains("X-Timestamp:timestampZ\r\n")
    check request.contains(">A &amp; B</prosody>")

  test "turn and audio parsing":
    check parseTextResponse(encodeText("X:a\r\nPath:turn.end\r\n\r\n")).turnEnded
    let audio = parseBinaryResponse(binaryMessage(
      "Path:audio\r\nContent-Type:audio/mpeg\r\n", [0xFF'u8, 0xFB'u8, 0x01'u8]))
    check audio.chunks.len == 1
    check audio.chunks[0].kind == Audio
    check audio.chunks[0].data == @[0xFF'u8, 0xFB'u8, 0x01'u8]
    check parseBinaryResponse(binaryMessage("Path:audio\r\n")).chunks.len == 0

  test "custom output format request and audio content types":
    var custom = config
    custom.outputFormat = "audio-24khz-96kbitrate-mono-mp3"
    let body = speechConfigRequest(custom).split("\r\n\r\n", 1)[1]
    check parseJson(body)["context"]["synthesis"]["audio"]["outputFormat"].getStr() ==
      custom.outputFormat

    let audio = parseBinaryResponse(binaryMessage(
      "Path:audio\r\nContent-Type:audio/webm; codecs=opus\r\n", [1'u8, 2'u8]),
      "webm-24khz-16bit-mono-opus")
    check audio.chunks.len == 1
    check audio.chunks[0].data == @[1'u8, 2'u8]

    expect UnexpectedResponseError:
      discard parseBinaryResponse(binaryMessage(
        "Path:audio\r\nContent-Type:video/mp4\r\n", [1'u8]))

  test "multiple metadata events and offset compensation":
    let body = """{"Metadata":[
      {"Type":"WordBoundary","Data":{"Offset":100,"Duration":20,"text":{"Text":"A&amp;B"}}},
      {"Type":"SessionEnd"},
      {"Type":"SentenceBoundary","Data":{"Offset":300,"Duration":50,"text":{"Text":"Done"}}}
    ]}"""
    let parsed = parseTextResponse(encodeText(
      "Path:audio.metadata\r\n\r\n" & body), 1000)
    check parsed.chunks.len == 2
    check parsed.chunks[0].kind == WordBoundary
    check parsed.chunks[0].offset == 1100
    check parsed.chunks[0].text == "A&B"
    check parsed.chunks[1].kind == SentenceBoundary
    check parsed.chunks[1].offset == 1300
    check parseJson(metadataJson(parsed.chunks[0]))["offset"].getInt() == 1100

  test "malformed and unknown responses":
    expect UnexpectedResponseError:
      discard parseBinaryResponse(@[1'u8])
    expect UnexpectedResponseError:
      discard parseTextResponse(encodeText("missing separator"))
    expect UnknownResponseError:
      discard parseTextResponse(encodeText("Path:unknown\r\n\r\n"))
    expect UnexpectedResponseError:
      discard parseBinaryResponse(binaryMessage("Path:audio\r\n", [1'u8]))
