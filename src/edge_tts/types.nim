import chronos

type
  EdgeTtsError* = object of CatchableError
  ConfigurationError* = object of EdgeTtsError
  EdgeNetworkError* = object of EdgeTtsError
  UnexpectedResponseError* = object of EdgeTtsError
  UnknownResponseError* = object of EdgeTtsError
  NoAudioReceivedError* = object of EdgeTtsError

  BoundaryKind* {.pure.} = enum
    SentenceBoundary
    WordBoundary

  TtsConfig* = object
    voice*: string
    rate*: string
    volume*: string
    pitch*: string
    boundary*: BoundaryKind
    outputFormat*: string

  TtsChunkKind* {.pure.} = enum
    Audio
    SentenceBoundary
    WordBoundary

  TtsChunk* = object
    kind*: TtsChunkKind
    data*: seq[byte]
    offset*: int64
    duration*: int64
    text*: string

  ChunkCallback* = proc(chunk: TtsChunk) {.closure, gcsafe, raises: [CatchableError].}

  Voice* = object
    name*: string
    shortName*: string
    friendlyName*: string
    locale*: string
    gender*: string
    suggestedCodec*: string
    status*: string
    contentCategories*: seq[string]
    voicePersonalities*: seq[string]

  ClientOptions* = object
    connectTimeout*: Duration
    receiveTimeout*: Duration
    clockSkewSeconds*: float64

proc defaultClientOptions*(): ClientOptions =
  ClientOptions(connectTimeout: 10.seconds, receiveTimeout: 60.seconds)

proc audioChunk*(data: seq[byte]): TtsChunk =
  TtsChunk(kind: Audio, data: data)

proc metadataChunk*(kind: TtsChunkKind, offset, duration: int64,
                    text: string): TtsChunk =
  TtsChunk(kind: kind, offset: offset, duration: duration, text: text)
