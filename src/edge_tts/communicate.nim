import std/uri
import chronos
import chronicles
import websock/websock
import ./[constants, protocol, text, token, types]

type
  Communicate* = ref object
    texts: seq[string]
    config: TtsConfig
    options: ClientOptions
    streamWasCalled: bool
    offsetCompensation: int64
    cumulativeAudioBytes: int64

proc newCommunicate*(text: string, voice = DefaultVoice, rate = "+0%",
    volume = "+0%", pitch = "+0Hz", boundary = BoundaryKind.SentenceBoundary,
    options = defaultClientOptions()): Communicate =
  if text.len == 0:
    raise newException(ConfigurationError, "text must not be empty")
  if options.connectTimeout <= 0.seconds or options.receiveTimeout <= 0.seconds:
    raise newException(ConfigurationError, "timeouts must be greater than zero")

  let config = validateConfig(TtsConfig(voice: voice, rate: rate, volume: volume,
    pitch: pitch, boundary: boundary))
  let cleaned = removeIncompatibleCharacters(text)
  let escaped = escapeXml(cleaned)
  let chunks = splitTextByByteLength(escaped, MaxTextBytes)
  if chunks.len == 0:
    raise newException(ConfigurationError, "text must contain visible characters")
  Communicate(texts: chunks, config: config, options: options)

proc config*(communicate: Communicate): TtsConfig =
  communicate.config

proc handshakeHook(muid: string): Hook =
  result = Hook()
  result.append = proc(ctx: Hook, headers: var HttpTable): Result[void, string] {.
      closure, gcsafe, raises: [].} =
    headers.add("Pragma", "no-cache")
    headers.add("Cache-Control", "no-cache")
    headers.add("Origin", Origin)
    headers.add("User-Agent", UserAgent)
    headers.add("Accept-Encoding", "gzip, deflate, br, zstd")
    headers.add("Accept-Language", "en-US,en;q=0.9")
    headers.add("Cookie", "muid=" & muid & ";")
    ok()

proc webSocketUrl(communicate: Communicate): string =
  WssUrl & "&ConnectionId=" & connectId() & "&Sec-MS-GEC=" &
    currentSecMsGec(communicate.options.clockSkewSeconds) &
    "&Sec-MS-GEC-Version=" & SecMsGecVersion

proc connectWebSocket(communicate: Communicate): Future[WSSession] {.async: (raises: [CatchableError, CancelledError]).} =
  let uri = parseUri(communicate.webSocketUrl())
  try:
    return await WebSocket.connect(
      host = uri.hostname & ":443",
      path = uri.path & "?" & uri.query,
      hostName = uri.hostname,
      hooks = @[handshakeHook(generateMuid())],
      secure = true).wait(communicate.options.connectTimeout)
  except CancelledError:
    raise
  except CatchableError as exc:
    raise newException(EdgeNetworkError, "WebSocket connection failed: " & exc.msg)

proc sendText(ws: WSSession, text: string) {.async: (raises: [CatchableError, CancelledError]).} =
  try:
    await ws.send(text)
  except CancelledError:
    raise
  except CatchableError as exc:
    raise newException(EdgeNetworkError, "WebSocket send failed: " & exc.msg)

proc receiveMessage(ws: WSSession, timeout: Duration):
    Future[tuple[data: seq[byte], binary: bool]] {.async: (raises: [CatchableError, CancelledError]).} =
  try:
    let data = await ws.recvMsg().wait(timeout)
    (data, ws.binary)
  except CancelledError:
    raise
  except CatchableError as exc:
    raise newException(EdgeNetworkError, "WebSocket receive failed: " & exc.msg)

proc streamPart(communicate: Communicate, partialText: string,
                onChunk: ChunkCallback): Future[int64] {.async: (raises: [CatchableError, CancelledError]).} =
  let ws = await communicate.connectWebSocket()
  var audioWasReceived = false
  var audioBytes = 0'i64
  try:
    await sendText(ws, speechConfigRequest(communicate.config))
    await sendText(ws, ssmlRequest(connectId(), dateToString(),
      communicate.config, partialText))

    var turnEnded = false
    while not turnEnded:
      let message = await receiveMessage(ws, communicate.options.receiveTimeout)
      let parsed = parseResponse(message.binary, message.data,
        communicate.offsetCompensation)
      for chunk in parsed.chunks:
        if chunk.kind == Audio:
          audioWasReceived = true
          audioBytes += chunk.data.len
        onChunk(chunk)
      turnEnded = parsed.turnEnded

    if not audioWasReceived:
      raise newException(NoAudioReceivedError,
        "No audio was received; verify the text and synthesis parameters")
    audioBytes
  finally:
    await ws.close()

proc stream*(communicate: Communicate, onChunk: ChunkCallback) {.async: (raises: [CatchableError, CancelledError]).} =
  if onChunk.isNil:
    raise newException(ConfigurationError, "onChunk must not be nil")
  if communicate.streamWasCalled:
    raise newException(EdgeTtsError, "stream can only be called once")
  communicate.streamWasCalled = true

  for partialText in communicate.texts:
    let audioBytes = await communicate.streamPart(partialText, onChunk)
    communicate.cumulativeAudioBytes += audioBytes
    communicate.offsetCompensation = communicate.cumulativeAudioBytes * 8 *
      TicksPerSecond div Mp3BitrateBps

proc save*(communicate: Communicate, audioPath: string,
           metadataPath = "") {.async: (raises: [CatchableError, CancelledError]).} =
  let audioFile = open(audioPath, fmWrite)
  var metadataFile: File
  if metadataPath.len > 0:
    try:
      metadataFile = open(metadataPath, fmWrite)
    except CatchableError:
      audioFile.close()
      raise
  defer:
    audioFile.close()
    if not metadataFile.isNil:
      metadataFile.close()

  proc onChunk(chunk: TtsChunk) {.closure, gcsafe.} =
    case chunk.kind
    of Audio:
      if chunk.data.len > 0:
        let written = audioFile.writeBuffer(unsafeAddr chunk.data[0], chunk.data.len)
        if written != chunk.data.len:
          raise newException(IOError, "Could not write the complete audio chunk")
    of SentenceBoundary, WordBoundary:
      if not metadataFile.isNil:
        metadataFile.writeLine(metadataJson(chunk))

  await communicate.stream(onChunk)
