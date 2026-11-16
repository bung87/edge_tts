import std/[json, strutils, tables]
import ./[constants, formats, text, token, types]

type
  ParsedResponse* = object
    turnEnded*: bool
    chunks*: seq[TtsChunk]

proc bytesToString(data: openArray[byte]): string =
  result = newString(data.len)
  for i, value in data:
    result[i] = char(value)

proc stringToBytes(text: string): seq[byte] =
  result = newSeq[byte](text.len)
  for i, ch in text:
    result[i] = byte(ch)

proc parseHeaders(headerData: string): Table[string, string] =
  result = initTable[string, string]()
  for line in headerData.split("\r\n"):
    if line.len == 0:
      continue
    let separator = line.find(':')
    if separator <= 0:
      raise newException(UnexpectedResponseError, "Malformed response header")
    result[toLowerAscii(line[0 ..< separator])] = line[separator + 1 .. ^1]

proc splitHeadersAndData(data: openArray[byte], headerLength: int):
    tuple[headers: Table[string, string], body: seq[byte]] =
  if headerLength < 0 or headerLength > data.len:
    raise newException(UnexpectedResponseError, "Invalid response header length")
  result.headers = parseHeaders(bytesToString(data.toOpenArray(0, headerLength - 1)))
  let bodyStart = headerLength + 2
  if bodyStart > data.len:
    raise newException(UnexpectedResponseError, "Response is missing its body separator")
  if bodyStart < data.len:
    result.body = @(data.toOpenArray(bodyStart, data.high))

proc speechConfigRequest*(config: TtsConfig): string =
  let wordBoundary = if config.boundary == WordBoundary: "true" else: "false"
  let sentenceBoundary = if config.boundary == SentenceBoundary: "true" else: "false"
  let outputFormat = if config.outputFormat.len == 0: DefaultOutputFormat
                     else: config.outputFormat
  "X-Timestamp:" & dateToString() & "\r\n" &
    "Content-Type:application/json; charset=utf-8\r\n" &
    "Path:speech.config\r\n\r\n" &
    "{\"context\":{\"synthesis\":{\"audio\":{\"metadataoptions\":{" &
    "\"sentenceBoundaryEnabled\":\"" & sentenceBoundary & "\"," &
    "\"wordBoundaryEnabled\":\"" & wordBoundary & "\"}," &
    "\"outputFormat\":\"" & outputFormat & "\"}}}}"

proc buildSsml*(config: TtsConfig, escapedText: string): string =
  let voice = config.voice.replace("&", "&amp;").replace("'", "&apos;")
    .replace("<", "&lt;").replace(">", "&gt;")
  "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' " &
    "xml:lang='en-US'><voice name='" & voice & "'><prosody pitch='" &
    config.pitch & "' rate='" & config.rate & "' volume='" & config.volume &
    "'>" & escapedText & "</prosody></voice></speak>"

proc ssmlRequest*(requestId, timestamp: string, config: TtsConfig,
                  escapedText: string): string =
  "X-RequestId:" & requestId & "\r\n" &
    "Content-Type:application/ssml+xml\r\n" &
    "X-Timestamp:" & timestamp & "Z\r\n" &
    "Path:ssml\r\n\r\n" & buildSsml(config, escapedText)

proc parseMetadata(body: openArray[byte], offsetCompensation: int64): seq[TtsChunk] =
  var document: JsonNode
  try:
    document = parseJson(bytesToString(body))
  except CatchableError as exc:
    raise newException(UnexpectedResponseError,
      "Invalid audio metadata: " & exc.msg)

  let events = document.getOrDefault("Metadata")
  if events.isNil or events.kind != JArray:
    raise newException(UnexpectedResponseError, "Metadata array is missing")

  for event in events.elems:
    let eventType = event.getOrDefault("Type").getStr()
    case eventType
    of "WordBoundary", "SentenceBoundary":
      let data = event.getOrDefault("Data")
      let textNode = if data.isNil: nil else: data.getOrDefault("text")
      if data.isNil or textNode.isNil:
        raise newException(UnexpectedResponseError, "Incomplete boundary metadata")
      let kind = if eventType == "WordBoundary": TtsChunkKind.WordBoundary
                 else: TtsChunkKind.SentenceBoundary
      result.add(metadataChunk(kind,
        data.getOrDefault("Offset").getBiggestInt() + offsetCompensation,
        data.getOrDefault("Duration").getBiggestInt(),
        unescapeXml(textNode.getOrDefault("Text").getStr())))
    of "SessionEnd":
      continue
    else:
      raise newException(UnknownResponseError, "Unknown metadata type: " & eventType)

  if events.elems.len == 0:
    raise newException(UnexpectedResponseError, "Metadata array is empty")

proc parseTextResponse*(data: openArray[byte], offsetCompensation = 0'i64): ParsedResponse =
  let text = bytesToString(data)
  let headerLength = text.find("\r\n\r\n")
  if headerLength < 0:
    raise newException(UnexpectedResponseError, "Text response has no header terminator")
  let (headers, body) = splitHeadersAndData(data, headerLength)
  let path = headers.getOrDefault("path")
  case path
  of "audio.metadata":
    result.chunks = parseMetadata(body, offsetCompensation)
  of "turn.end":
    result.turnEnded = true
  of "response", "turn.start":
    discard
  else:
    raise newException(UnknownResponseError, "Unknown response path: " & path)

proc parseBinaryResponse*(data: openArray[byte],
                          outputFormat = DefaultOutputFormat): ParsedResponse =
  if data.len < 2:
    raise newException(UnexpectedResponseError,
      "Binary response is missing its header length")
  let headerLength = int(data[0]) shl 8 or int(data[1])
  if headerLength < 2 or headerLength + 2 > data.len:
    raise newException(UnexpectedResponseError, "Invalid binary response header length")
  let headers = parseHeaders(bytesToString(data.toOpenArray(2, headerLength - 1)))
  var body: seq[byte]
  let bodyStart = headerLength + 2
  if bodyStart < data.len:
    body = @(data.toOpenArray(bodyStart, data.high))
  if headers.getOrDefault("path") != "audio":
    raise newException(UnexpectedResponseError, "Binary response path is not audio")

  if not headers.contains("content-type"):
    if body.len == 0:
      return
    raise newException(UnexpectedResponseError,
      "Binary response without Content-Type contains data")
  let format = getOutputFormat(outputFormat)
  if not format.acceptsContentType(headers.getOrDefault("content-type")):
    raise newException(UnexpectedResponseError,
      "Unexpected audio Content-Type for " & outputFormat)
  if body.len == 0:
    raise newException(UnexpectedResponseError, "Audio response contains no data")
  result.chunks.add(audioChunk(body))

proc parseResponse*(binary: bool, data: openArray[byte],
                    offsetCompensation = 0'i64,
                    outputFormat = DefaultOutputFormat): ParsedResponse =
  if binary:
    parseBinaryResponse(data, outputFormat)
  else:
    parseTextResponse(data, offsetCompensation)

proc metadataJson*(chunk: TtsChunk): string =
  let kind = if chunk.kind == TtsChunkKind.WordBoundary: "WordBoundary"
             else: "SentenceBoundary"
  $(%*{"type": kind, "offset": chunk.offset, "duration": chunk.duration,
       "text": chunk.text})

proc encodeText*(text: string): seq[byte] =
  stringToBytes(text)
