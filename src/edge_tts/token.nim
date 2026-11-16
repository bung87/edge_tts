import std/[math, strutils, times]
import uuids
import ./constants

const
  WinEpoch = 11_644_473_600.0
  Sha256Initial = [0x6A09E667'u32, 0xBB67AE85'u32, 0x3C6EF372'u32,
    0xA54FF53A'u32, 0x510E527F'u32, 0x9B05688C'u32, 0x1F83D9AB'u32,
    0x5BE0CD19'u32]
  Sha256State = [0xFD9FBEA2'u32, 0x91243CE7'u32, 0xBE499094'u32,
    0xCD2E1E0A'u32, 0x6C006F49'u32, 0x04BD35AB'u32, 0xFEB0A7E4'u32,
    0x03EFFBD2'u32]
  Sha256Schedule = [0xEB24BF9E'u32, 0x1558691F'u32, 0xA0C09EE2'u32,
    0x0CFA32BA'u32, 0xA622EE8C'u32, 0xD1DD9491'u32, 0xC0DD25A0'u32,
    0xF9E70AB6'u32, 0xF0C31573'u32, 0x7058CE4E'u32, 0x7188E606'u32,
    0x00E5AB33'u32, 0xD258B060'u32, 0x72766564'u32]
  Sha256RoundConstants = [0x428A2F98'u32, 0x71374491'u32, 0xB5C0FBCF'u32,
    0xE9B5DBA5'u32, 0x3956C25B'u32, 0x59F111F1'u32, 0x923F82A4'u32,
    0xAB1C5ED5'u32, 0xD807AA98'u32, 0x12835B01'u32, 0x243185BE'u32,
    0x550C7DC3'u32, 0x72BE5D74'u32, 0x80DEB1FE'u32, 0x9BDC06A7'u32,
    0xC19BF174'u32, 0xE49B69C1'u32, 0xEFBE4786'u32, 0x0FC19DC6'u32,
    0x240CA1CC'u32, 0x2DE92C6F'u32, 0x4A7484AA'u32, 0x5CB0A9DC'u32,
    0x76F988DA'u32, 0x983E5152'u32, 0xA831C66D'u32, 0xB00327C8'u32,
    0xBF597FC7'u32, 0xC6E00BF3'u32, 0xD5A79147'u32, 0x06CA6351'u32,
    0x14292967'u32, 0x27B70A85'u32, 0x2E1B2138'u32, 0x4D2C6DFC'u32,
    0x53380D13'u32, 0x650A7354'u32, 0x766A0ABB'u32, 0x81C2C92E'u32,
    0x92722C85'u32, 0xA2BFE8A1'u32, 0xA81A664B'u32, 0xC24B8B70'u32,
    0xC76C51A3'u32, 0xD192E819'u32, 0xD6990624'u32, 0xF40E3585'u32,
    0x106AA070'u32, 0x19A4C116'u32, 0x1E376C08'u32, 0x2748774C'u32,
    0x34B0BCB5'u32, 0x391C0CB3'u32, 0x4ED8AA4A'u32, 0x5B9CCA4F'u32,
    0x682E6FF3'u32, 0x748F82EE'u32, 0x78A5636F'u32, 0x84C87814'u32,
    0x8CC70208'u32, 0x90BEFFFA'u32, 0xA4506CEB'u32, 0xBEF9A3F7'u32,
    0xC67178F2'u32]
  Sha256Adjustment = 0xC9DC06A7'u32
  Sha256Sigma0Adjustment = 0x059C0B80'u32
  Sha256Sigma1Adjustment = 0x000B92C0'u32
  Cs64Coefficients = [(0xE82E91B1'u32, 0xB32700D0'u32),
    (0x44DE24C6'u32, 0x88DFF51D'u32), (0x3BEB65BC'u32, 0x29514038'u32),
    (0xC89C5933'u32, 0xB328CBDF'u32), (0x8D1EC211'u32, 0xD405B4D5'u32),
    (0x314EF5D5'u32, 0x26E55F3C'u32), (0xE92491B1'u32, 0x607801C6'u32),
    (0xF0A5B9D5'u32, 0x82B2C1FB'u32), (0x06064CF3'u32, 0xFA51A3DA'u32),
    (0xDA79FA60'u32, 0x207CC464'u32), (0xBED20560'u32, 0x3C3C74F3'u32),
    (0x89F9C9F8'u32, 0xD2D14B61'u32), (0x35FA38C6'u32, 0xBB04A2C1'u32),
    (0xCB49E3C6'u32, 0xC5626167'u32)]
  Cs64Factor = 0x82893933'u32
  Cs64Adjustment0 = 0xF2F90B1A'u32
  Cs64Adjustment1 = 0x0B1A0000'u32

func rol16(value: uint32): uint32 =
  (value shl 16) or (value shr 16)

func rotr(value: uint32, amount: uint32): uint32 =
  (value shr amount) or (value shl (32 - amount))

func sigma0(value: uint32): uint32 =
  rotr(value, 7) xor rotr(value, 18) xor (value shr 3)

func sigma1(value: uint32): uint32 =
  rotr(value, 17) xor rotr(value, 19) xor (value shr 10)

func be32(data: openArray[byte]): uint32 =
  (uint32(data[0]) shl 24) or (uint32(data[1]) shl 16) or
    (uint32(data[2]) shl 8) or uint32(data[3])

func le32(data: openArray[byte]): uint32 =
  uint32(data[0]) or (uint32(data[1]) shl 8) or
    (uint32(data[2]) shl 16) or (uint32(data[3]) shl 24)

func appendBe32(output: var seq[byte], value: uint32) =
  output.add([byte(value shr 24), byte(value shr 16), byte(value shr 8), byte(value)])

func appendLe32(output: var seq[byte], value: uint32) =
  output.add([byte(value), byte(value shr 8), byte(value shr 16), byte(value shr 24)])

func expandSchedule(words: var seq[uint32], firstWord = 16) =
  for i in firstWord ..< 64:
    words.add(sigma1(words[i - 2]) + words[i - 7] + sigma0(words[i - 15]) +
      words[i - 16])

func sha256Rounds(initial: array[8, uint32], words: seq[uint32],
                  firstRound = 0): array[8, uint32] =
  var a = initial[0]
  var b = initial[1]
  var c = initial[2]
  var d = initial[3]
  var e = initial[4]
  var f = initial[5]
  var g = initial[6]
  var h = initial[7]
  for i in firstRound ..< 64:
    let constant = if firstRound == 14 and i == 14: Sha256Adjustment
                   else: Sha256RoundConstants[i]
    let t1 = h + (rotr(e, 6) xor rotr(e, 11) xor rotr(e, 25)) +
      (g xor (e and (f xor g))) + constant + words[i]
    let t2 = (rotr(a, 2) xor rotr(a, 13) xor rotr(a, 22)) +
      ((a and b) or (c and (a or b)))
    h = g
    g = f
    f = e
    e = d + t1
    d = c
    c = b
    b = a
    a = t1 + t2
  [a, b, c, d, e, f, g, h]

func sha256Init(data: openArray[byte]): array[8, uint32] =
  var words = newSeq[uint32](14)
  words.add(uint32(data[0]) shl 16 or uint32(data[1]) shl 8 or uint32(data[2]))
  words.add(be32(data.toOpenArray(3, 6)))
  for i in 16 ..< 30:
    var value = Sha256Schedule[i - 16]
    if i - 2 >= 14:
      value += (if i == 16: sigma1(words[i - 2]) xor Sha256Sigma1Adjustment
                else: sigma1(words[i - 2]))
    if i - 7 >= 14:
      value += words[i - 7]
    if i - 15 >= 14:
      value += (if i == 29: sigma0(words[i - 15]) xor Sha256Sigma0Adjustment
                else: sigma0(words[i - 15]))
    words.add(value)
  words.add(sigma1(words[28]) + words[23] + sigma0(words[15]) + words[14] +
    Sha256Adjustment - Sha256RoundConstants[14])
  expandSchedule(words, 31)
  let working = sha256Rounds(Sha256State, words, 14)
  for i in 0 ..< 8:
    result[i] = Sha256Initial[i] + working[i]

func sha256Digest(data: openArray[byte]): seq[byte] =
  doAssert(data.len >= 7)
  let length = 57 + data.len
  var padded = @(data.toOpenArray(7, data.high))
  padded.add(0x80'u8)
  let zeroCount = ((55 - length) mod 64 + 64) mod 64
  padded.add(newSeq[byte](zeroCount))
  let bitLength = uint64(length * 8)
  for shift in countdown(56, 0, 8):
    padded.add(byte(bitLength shr shift))

  var state = sha256Init(data)
  for offset in countup(0, padded.high, 64):
    var words = newSeq[uint32](16)
    for i in 0 ..< 16:
      words[i] = be32(padded.toOpenArray(offset + i * 4, offset + i * 4 + 3))
    expandSchedule(words)
    let working = sha256Rounds(state, words)
    for i in 0 ..< 8:
      state[i] += working[i]
  for word in state:
    result.appendBe32(word)

func littleEndianWords(data: openArray[byte]): seq[uint32] =
  var padded = @data
  while padded.len mod 4 != 0:
    padded.add(0)
  for offset in countup(0, padded.high, 4):
    result.add(le32(padded.toOpenArray(offset, offset + 3)))
  if result.len mod 2 != 0:
    result.add(0)

func cs64Digest(data: openArray[byte], digest: openArray[byte]): tuple[a, b: uint32] =
  var keyA = le32(digest.toOpenArray(0, 3)) or 1'u32
  var keyB = le32(digest.toOpenArray(4, 7)) or 1'u32
  let factors = [keyA * Cs64Factor, keyB * Cs64Factor]
  var terms = newSeqOfCap[uint32](32)
  var offsets = newSeqOfCap[uint32](32)
  for i, pair in Cs64Coefficients:
    terms.add(pair[0] * factors[i mod 2])
    offsets.add(pair[1])

  var prefixed = newSeqOfCap[byte](data.len + 1)
  prefixed.add(0)
  prefixed.add(data)
  for i, word in littleEndianWords(prefixed):
    var term = word * (if i mod 2 == 0: keyA else: keyB)
    var offset = rol16(word) * (if i mod 2 == 0: 0xEF0569FB'u32 else: 0xC31713DB'u32)
    if i == 0:
      term += Cs64Adjustment0 * factors[0]
      offset += Cs64Adjustment1
    terms.add(term)
    offsets.add(offset)

  var swapAcc = 0'u32
  var swapLast = 0'u32
  var state = 0'u32
  var acc = 0'u32
  for i in countup(0, terms.high, 2):
    let x = terms[i]
    let y = terms[i + 1]
    var t = rol16(offsets[i] + x)
    var q = t * 0x76F50F34'u32
    swapAcc += rol16(q) * 0xC3EFEA97'u32 + q
    t = rol16(offsets[i + 1] + y)
    q = t * 0x1881CE3C'u32
    swapLast = rol16(q) * 0x35BD1EC9'u32 + q
    swapAcc += swapLast

    state = state * keyA + x
    state = rol16(state) * 0xCF98B111'u32
    state = rol16(state) * 0x87085B9F'u32
    state = rol16(state) * 0x12CEB96D'u32
    state = rol16(state) * 0x257E1D83'u32
    acc += state
    t = state * keyB + y
    t = rol16(t) * 0xA27416F5'u32
    t = rol16(t) * 0xD38396FF'u32
    state = rol16(rol16(t) * 0x7C932B89'u32) * 0xBFA49F69'u32
    acc += state
  (swapLast xor state, swapAcc xor acc)

func hexUpper(data: openArray[byte]): string =
  const digits = "0123456789ABCDEF"
  result = newStringOfCap(data.len * 2)
  for value in data:
    result.add(digits[value shr 4])
    result.add(digits[value and 0x0F])

proc generateSecMsGec*(unixTimestamp: float64): string =
  var ticks = unixTimestamp + WinEpoch
  ticks = floor(ticks / 300.0) * 300.0
  let windowsTicks = uint64(ticks * 10_000_000.0)
  let text = $windowsTicks & TrustedClientToken
  var data = newSeq[byte](text.len)
  for i, ch in text:
    data[i] = byte(ch)
  let digest = sha256Digest(data)
  let cs64 = cs64Digest(data, digest)
  var cs64Bytes: seq[byte]
  cs64Bytes.appendLe32(cs64.a)
  cs64Bytes.appendLe32(cs64.b)
  hexUpper(cs64Bytes) & "-" & hexUpper(digest)

proc currentSecMsGec*(clockSkewSeconds: float64 = 0.0): string =
  generateSecMsGec(epochTime() + clockSkewSeconds)

proc connectId*(): string =
  ($genUUID()).replace("-", "")

proc generateMuid*(): string =
  connectId().toUpperAscii()

proc dateToString*(now = times.now().utc): string =
  now.format("ddd MMM dd yyyy HH:mm:ss") &
    " GMT+0000 (Coordinated Universal Time)"
