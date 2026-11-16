import std/unittest
import edge_tts/[types, webm]

proc element(id: openArray[byte], body: openArray[byte]): seq[byte] =
  doAssert(body.len < 128)
  result = @id
  result.add(byte(0x80 or body.len))
  result.add(body)

proc containsBytes(data: openArray[byte], needle: openArray[byte]): bool =
  if needle.len == 0 or needle.len > data.len:
    return false
  for i in 0 .. data.len - needle.len:
    if data.toOpenArray(i, i + needle.len - 1) == needle:
      return true

proc sampleWebM(): seq[byte] =
  let ebml = element([0x1A'u8, 0x45, 0xDF, 0xA3],
    [0x42'u8, 0x82, 0x85, 0x77, 0x65, 0x62, 0x6D, 0x00])
  let scale = element([0x2A'u8, 0xD7, 0xB1], [0x0F'u8, 0x42, 0x40])
  let info = element([0x15'u8, 0x49, 0xA9, 0x66], scale)
  let tracks = element([0x16'u8, 0x54, 0xAE, 0x6B], [])
  let timestamp = element([0xE7'u8], [0x00'u8])
  let blockData = [0x81'u8, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04]
  let audioBlock = element([0xA3'u8], blockData)
  var clusterBody = timestamp
  clusterBody.add(audioBlock)
  let cluster = element([0x1F'u8, 0x43, 0xB6, 0x75], clusterBody)

  result = ebml
  result.add([0x18'u8, 0x53, 0x80, 0x67,
    0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
  result.add(info)
  result.add(tracks)
  result.add(cluster)

suite "WebM finalization":
  test "adds duration and indexes without changing audio":
    let source = sampleWebM()
    let finalized = finalizeWebM(source)
    check finalized.len > source.len
    check finalized.containsBytes([0x11'u8, 0x4D, 0x9B, 0x74]) # SeekHead
    check finalized.containsBytes([0x1C'u8, 0x53, 0xBB, 0x6B]) # Cues
    check finalized.containsBytes([0x44'u8, 0x89, 0x88]) # Duration, float64
    check finalized.containsBytes([0xA3'u8, 0x88, 0x81, 0x00, 0x00, 0x00,
      0x01, 0x02, 0x03, 0x04])
    check finalizeWebM(finalized) == finalized

  test "rejects malformed input":
    expect UnexpectedResponseError:
      discard finalizeWebM([0x01'u8, 0x02, 0x03])
    expect UnexpectedResponseError:
      discard finalizeWebM([])
