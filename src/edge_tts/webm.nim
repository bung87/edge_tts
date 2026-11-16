import ./types

const
  IdEbml = 0x1A45DFA3'u32
  IdSegment = 0x18538067'u32
  IdSeekHead = 0x114D9B74'u32
  IdSeek = 0x4DBB'u32
  IdSeekId = 0x53AB'u32
  IdSeekPosition = 0x53B8'u32
  IdInfo = 0x1549A966'u32
  IdTimestampScale = 0x2AD7B1'u32
  IdDuration = 0x4489'u32
  IdTracks = 0x1654AE6B'u32
  IdCues = 0x1C53BB6B'u32
  IdCuePoint = 0xBB'u32
  IdCueTime = 0xB3'u32
  IdCueTrackPositions = 0xB7'u32
  IdCueTrack = 0xF7'u32
  IdCueClusterPosition = 0xF1'u32
  IdCluster = 0x1F43B675'u32
  IdTimestamp = 0xE7'u32
  IdSimpleBlock = 0xA3'u32
  IdBlockGroup = 0xA0'u32
  IdBlock = 0xA1'u32
  IdVoid = 0xEC'u32

type
  ElementView = object
    id: uint32
    start: int
    contentStart: int
    contentEnd: int
    finish: int
    unknownSize: bool

  ClusterInfo = object
    payload: seq[byte]
    firstCueTime: uint64
    lastTime: uint64
    track: uint64

  CueInfo = object
    time: uint64
    track: uint64
    clusterPosition: uint64

proc fail(message: string): void {.noreturn.} =
  raise newException(UnexpectedResponseError, "Invalid WebM: " & message)

proc idLength(first: byte): int =
  if (first and 0x80) != 0: 1
  elif (first and 0x40) != 0: 2
  elif (first and 0x20) != 0: 3
  elif (first and 0x10) != 0: 4
  else: fail("invalid element ID")

proc readId(data: openArray[byte], pos: int): uint32 =
  if pos < 0 or pos >= data.len:
    fail("truncated element ID")
  let length = idLength(data[pos])
  if pos + length > data.len:
    fail("truncated element ID")
  for i in 0 ..< length:
    result = (result shl 8) or uint32(data[pos + i])

proc vintLength(first: byte): int =
  for length in 1 .. 8:
    if (first and byte(0x80 shr (length - 1))) != 0:
      return length
  fail("invalid variable-length integer")

proc readVint(data: openArray[byte], pos: int, isSize: bool):
    tuple[value: uint64, length: int, unknown: bool] =
  if pos < 0 or pos >= data.len:
    fail("truncated variable-length integer")
  let length = vintLength(data[pos])
  if pos + length > data.len:
    fail("truncated variable-length integer")
  let marker = byte(0x80 shr (length - 1))
  var value = uint64(if isSize: data[pos] and (marker - 1) else: data[pos])
  for i in 1 ..< length:
    value = (value shl 8) or uint64(data[pos + i])
  let unknown = isSize and value == ((1'u64 shl (7 * length)) - 1)
  (value, length, unknown)

proc readElement(data: openArray[byte], pos, limit: int): ElementView =
  let id = readId(data, pos)
  let idLen = idLength(data[pos])
  let sizePos = pos + idLen
  if sizePos >= limit:
    fail("missing element size")
  let (size, sizeLen, unknown) = readVint(data, sizePos, true)
  let contentStart = sizePos + sizeLen
  if contentStart > limit:
    fail("truncated element header")
  var contentEnd = limit
  if not unknown:
    if size > uint64(limit - contentStart):
      fail("truncated element payload")
    contentEnd = contentStart + int(size)
  ElementView(id: id, start: pos, contentStart: contentStart,
    contentEnd: contentEnd, finish: contentEnd, unknownSize: unknown)

proc payload(data: openArray[byte], element: ElementView): seq[byte] =
  @(data.toOpenArray(element.contentStart, element.contentEnd - 1))

proc rawElement(data: openArray[byte], element: ElementView): seq[byte] =
  @(data.toOpenArray(element.start, element.finish - 1))

proc encodeId(id: uint32): seq[byte] =
  let length = if id > 0xFF_FFFF'u32: 4
               elif id > 0xFFFF'u32: 3
               elif id > 0xFF'u32: 2
               else: 1
  for shift in countdown((length - 1) * 8, 0, 8):
    result.add(byte(id shr shift))

proc encodeUInt(value: uint64, fixedWidth = 0): seq[byte] =
  var width = fixedWidth
  if width == 0:
    width = 1
    while width < 8 and value >= (1'u64 shl (width * 8)):
      inc(width)
  if width < 1 or width > 8 or (width < 8 and value >= (1'u64 shl (width * 8))):
    fail("integer does not fit its encoded width")
  for shift in countdown((width - 1) * 8, 0, 8):
    result.add(byte(value shr shift))

proc encodeSize(value: uint64, fixedWidth = 0): seq[byte] =
  var width = fixedWidth
  if width == 0:
    width = 1
    while width < 8 and value >= ((1'u64 shl (7 * width)) - 1):
      inc(width)
  if width < 1 or width > 8 or value >= ((1'u64 shl (7 * width)) - 1):
    fail("element is too large")
  result = encodeUInt(value, width)
  let marker = byte(0x80 shr (width - 1))
  result[0] = result[0] or marker

proc makeSizedElement(id: uint32, body: openArray[byte], sizeWidth: int): seq[byte] =
  result = encodeId(id)
  result.add(encodeSize(uint64(body.len), sizeWidth))
  result.add(body)

proc makeElement(id: uint32, body: openArray[byte]): seq[byte] =
  makeSizedElement(id, body, 0)

proc makeUIntElement(id: uint32, value: uint64, width = 0): seq[byte] =
  makeElement(id, encodeUInt(value, width))

proc uintValue(data: openArray[byte]): uint64 =
  if data.len == 0 or data.len > 8:
    fail("invalid unsigned integer")
  for value in data:
    result = (result shl 8) or uint64(value)

proc parseBlock(data: openArray[byte], clusterTime: uint64,
                track: var uint64, firstTime: var uint64,
                lastTime: var uint64, haveBlock: var bool) =
  let trackVint = readVint(data, 0, false)
  let headerLen = trackVint.length + 3
  if data.len < headerLen:
    fail("truncated audio block")
  let relativeBits = (uint16(data[trackVint.length]) shl 8) or
    uint16(data[trackVint.length + 1])
  let relative = int64(cast[int16](relativeBits))
  let blockTime = int64(clusterTime) + relative
  if not haveBlock:
    track = trackVint.value
    firstTime = uint64(max(0'i64, blockTime))
    haveBlock = true
  elif track != trackVint.value:
    fail("multiple audio tracks are not supported")
  lastTime = uint64(max(0'i64, blockTime))

proc clusterEnd(data: openArray[byte], contentStart, limit: int): int =
  var pos = contentStart
  while pos < limit:
    let id = readId(data, pos)
    if id in [IdCluster, IdCues, IdInfo, IdTracks, IdSeekHead]:
      return pos
    let child = readElement(data, pos, limit)
    if child.unknownSize:
      fail("nested element with unknown size")
    pos = child.finish
  limit

proc parseCluster(data: openArray[byte], pos, limit: int):
    tuple[info: ClusterInfo, finish: int] =
  var view = readElement(data, pos, limit)
  if view.unknownSize:
    view.contentEnd = clusterEnd(data, view.contentStart, limit)
    view.finish = view.contentEnd
  result.finish = view.finish
  result.info.payload = payload(data, view)

  var haveTimestamp = false
  var clusterTime = 0'u64
  var haveBlock = false
  var childPos = view.contentStart
  while childPos < view.contentEnd:
    let child = readElement(data, childPos, view.contentEnd)
    if child.unknownSize:
      fail("cluster child with unknown size")
    case child.id
    of IdTimestamp:
      clusterTime = uintValue(payload(data, child))
      haveTimestamp = true
    of IdSimpleBlock:
      parseBlock(payload(data, child), clusterTime, result.info.track,
        result.info.firstCueTime, result.info.lastTime, haveBlock)
    of IdBlockGroup:
      var blockPos = child.contentStart
      while blockPos < child.contentEnd:
        let blockElement = readElement(data, blockPos, child.contentEnd)
        if blockElement.id == IdBlock:
          parseBlock(payload(data, blockElement), clusterTime, result.info.track,
            result.info.firstCueTime, result.info.lastTime, haveBlock)
        blockPos = blockElement.finish
    else:
      discard
    childPos = child.finish
  if not haveTimestamp:
    fail("cluster has no Timestamp")
  if not haveBlock:
    fail("cluster has no audio block")

proc makeFloatElement(id: uint32, value: float64): seq[byte] =
  let bits = cast[uint64](value)
  makeElement(id, encodeUInt(bits, 8))

proc makeSeekEntry(targetId: uint32, position: uint64): seq[byte] =
  var body = makeElement(IdSeekId, encodeId(targetId))
  body.add(makeUIntElement(IdSeekPosition, position, 8))
  makeElement(IdSeek, body)

proc makeSeekHead(infoPosition, cuesPosition: uint64): seq[byte] =
  var body = makeSeekEntry(IdInfo, infoPosition)
  body.add(makeSeekEntry(IdCues, cuesPosition))
  makeElement(IdSeekHead, body)

proc makeCue(cue: CueInfo): seq[byte] =
  var positions = makeUIntElement(IdCueTrack, cue.track)
  positions.add(makeUIntElement(IdCueClusterPosition, cue.clusterPosition, 8))
  var body = makeUIntElement(IdCueTime, cue.time)
  body.add(makeElement(IdCueTrackPositions, positions))
  makeElement(IdCuePoint, body)

proc makeCues(cues: openArray[CueInfo]): seq[byte] =
  var body: seq[byte]
  for cue in cues:
    body.add(makeCue(cue))
  makeElement(IdCues, body)

proc finalizeWebM*(data: openArray[byte]): seq[byte] =
  if data.len < 4 or readId(data, 0) != IdEbml:
    fail("missing EBML header")
  let ebml = readElement(data, 0, data.len)
  if ebml.unknownSize:
    fail("unknown EBML header size")
  let segment = readElement(data, ebml.finish, data.len)
  if segment.id != IdSegment:
    fail("missing Segment")
  let segmentEnd = if segment.unknownSize: data.len else: segment.contentEnd
  if segmentEnd > data.len:
    fail("truncated Segment")

  var infoBody: seq[byte]
  var haveInfo = false
  var haveTracks = false
  var timestampScale = 1_000_000'u64
  var prefixItems: seq[seq[byte]]
  var clusters: seq[ClusterInfo]
  var pos = segment.contentStart

  while pos < segmentEnd:
    if readId(data, pos) == IdCluster:
      let (cluster, finish) = parseCluster(data, pos, segmentEnd)
      clusters.add(cluster)
      pos = finish
      continue
    let element = readElement(data, pos, segmentEnd)
    if element.unknownSize:
      fail("unsupported unknown-size Segment child")
    case element.id
    of IdInfo:
      haveInfo = true
      var childPos = element.contentStart
      while childPos < element.contentEnd:
        let child = readElement(data, childPos, element.contentEnd)
        case child.id
        of IdTimestampScale:
          timestampScale = uintValue(payload(data, child))
        of IdDuration:
          discard
        else:
          infoBody.add(rawElement(data, child))
        childPos = child.finish
    of IdTracks:
      haveTracks = true
      prefixItems.add(rawElement(data, element))
    of IdSeekHead, IdCues, IdVoid:
      discard
    else:
      prefixItems.add(rawElement(data, element))
    pos = element.finish

  if not haveInfo or not haveTracks or clusters.len == 0:
    fail("missing Info, Tracks, or audio Clusters")
  if timestampScale == 0:
    fail("TimestampScale is zero")

  var lastTime = 0'u64
  for cluster in clusters:
    lastTime = max(lastTime, cluster.lastTime)
  let frameTicks = (20_000_000'u64 + timestampScale - 1) div timestampScale
  let duration = float64(lastTime + frameTicks)
  infoBody.add(makeFloatElement(IdDuration, duration))
  let newInfo = makeElement(IdInfo, infoBody)

  let seekLength = makeSeekHead(0, 0).len
  var position = uint64(seekLength)
  let infoPosition = position
  position += uint64(newInfo.len)
  for item in prefixItems:
    position += uint64(item.len)

  var cues: seq[CueInfo]
  var encodedClusters: seq[seq[byte]]
  for cluster in clusters:
    let encoded = makeElement(IdCluster, cluster.payload)
    cues.add(CueInfo(time: cluster.firstCueTime, track: cluster.track,
      clusterPosition: position))
    position += uint64(encoded.len)
    encodedClusters.add(encoded)
  let cuesPosition = position
  let seekHead = makeSeekHead(infoPosition, cuesPosition)
  doAssert(seekHead.len == seekLength)
  let cueData = makeCues(cues)

  var segmentBody = seekHead
  segmentBody.add(newInfo)
  for item in prefixItems:
    segmentBody.add(item)
  for cluster in encodedClusters:
    segmentBody.add(cluster)
  segmentBody.add(cueData)

  result = rawElement(data, ebml)
  result.add(makeSizedElement(IdSegment, segmentBody, 8))
