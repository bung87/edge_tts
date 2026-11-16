import std/json
import chronos
import chronos/apps/http/httpclient
import ./[constants, token, types]

const VoiceHeaders = [
  ("User-Agent", UserAgent),
  ("Accept", "*/*"),
  ("Accept-Language", "en-US,en;q=0.9"),
  ("Sec-CH-UA", "\" Not;A Brand\";v=\"99\", \"Microsoft Edge\";v=\"143\", \"Chromium\";v=\"143\""),
  ("Sec-CH-UA-Mobile", "?0"),
  ("Sec-Fetch-Site", "none"),
  ("Sec-Fetch-Mode", "cors"),
  ("Sec-Fetch-Dest", "empty")
]

proc bytesToString(data: openArray[byte]): string =
  result = newString(data.len)
  for i, value in data:
    result[i] = char(value)

proc strings(node: JsonNode): seq[string] =
  if not node.isNil and node.kind == JArray:
    for item in node.elems:
      result.add(item.getStr())

proc parseVoice(node: JsonNode): Voice =
  let tag = node.getOrDefault("VoiceTag")
  result = Voice(
    name: node.getOrDefault("Name").getStr(),
    shortName: node.getOrDefault("ShortName").getStr(),
    friendlyName: node.getOrDefault("FriendlyName").getStr(),
    locale: node.getOrDefault("Locale").getStr(),
    gender: node.getOrDefault("Gender").getStr(),
    suggestedCodec: node.getOrDefault("SuggestedCodec").getStr(),
    status: node.getOrDefault("Status").getStr())
  if not tag.isNil:
    result.contentCategories = strings(tag.getOrDefault("ContentCategories"))
    result.voicePersonalities = strings(tag.getOrDefault("VoicePersonalities"))

proc listVoices*(options = defaultClientOptions()): Future[seq[Voice]] {.async.} =
  if options.connectTimeout <= 0.seconds:
    raise newException(ConfigurationError, "connectTimeout must be greater than zero")
  let session = HttpSessionRef.new(connectTimeout = options.connectTimeout,
    headersTimeout = options.receiveTimeout)
  defer:
    await session.closeWait()

  let url = VoiceListUrl & "&Sec-MS-GEC=" &
    currentSecMsGec(options.clockSkewSeconds) &
    "&Sec-MS-GEC-Version=" & SecMsGecVersion
  var headers = @VoiceHeaders
  headers.add(("Cookie", "muid=" & generateMuid() & ";"))

  try:
    let request = HttpClientRequestRef.get(session, url, headers = headers).valueOr:
      raise newException(EdgeNetworkError, "Invalid voice list URL: " & error)
    let response = await fetch(request)
    await request.closeWait()
    if response.status < 200 or response.status >= 300:
      raise newException(EdgeNetworkError,
        "Voice list request failed with HTTP status " & $response.status)
    let document = parseJson(bytesToString(response.data))
    if document.kind != JArray:
      raise newException(UnexpectedResponseError, "Voice list is not a JSON array")
    for item in document.elems:
      result.add(parseVoice(item))
  except EdgeTtsError:
    raise
  except CancelledError:
    raise
  except CatchableError as exc:
    raise newException(EdgeNetworkError, "Voice list request failed: " & exc.msg)
