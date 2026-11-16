import std/[strutils, times, unittest]
import edge_tts/token

suite "request tokens":
  test "connection id and MUID":
    let first = connectId()
    let second = connectId()
    check first.len == 32
    check not first.contains('-')
    check first != second
    let muid = generateMuid()
    check muid.len == 32
    check muid == muid.toUpperAscii()

  test "JavaScript-style UTC date":
    check dateToString(fromUnix(1_700_000_000).utc) ==
      "Tue Nov 14 2023 22:13:20 GMT+0000 (Coordinated Universal Time)"

  test "Sec-MS-GEC v2 reference vectors":
    check generateSecMsGec(0.0) ==
      "52BC7A17B50DFEC9-28C4394775C8751CD2F6859C030C06DB1489ACAB3B3A7651831FC26895177ED6"
    check generateSecMsGec(1_700_000_000.0) ==
      "2CD23A2CA0B2595A-F3C846C370E05F9CC83ACC5F995C5F5D87A4D0F14CE8936A0F902E64099E38A2"
    check generateSecMsGec(1_763_222_400.0) ==
      "CAB8C6FD53DE5E1C-3412F0110E410507E9C9759F5CDF97A87EE1E9B101CAA6E57D968B5DC1EE6B41"
    check generateSecMsGec(1_700_000_001.0) == generateSecMsGec(1_700_000_099.0)
