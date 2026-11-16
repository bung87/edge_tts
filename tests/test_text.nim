import std/[strutils, unittest]
import edge_tts/[text, types]

suite "text processing":
  test "control characters and XML escaping":
    check removeIncompatibleCharacters("a\0b\vc\td\ne") == "a b c\td\ne"
    check escapeXml("Tom & <Jerry>") == "Tom &amp; &lt;Jerry&gt;"
    check unescapeXml("&lt;a&amp;b&gt;") == "<a&b>"

  test "voice normalization and parameter validation":
    check normalizeVoice("en-US-EmmaMultilingualNeural") ==
      "Microsoft Server Speech Text to Speech Voice (en-US, EmmaMultilingualNeural)"
    check normalizeVoice("en-US-family-EmmaNeural") ==
      "Microsoft Server Speech Text to Speech Voice (en-US-family, EmmaNeural)"
    let config = validateConfig(TtsConfig(voice: "zh-CN-XiaoxiaoNeural",
      rate: "+10%", volume: "-5%", pitch: "+2Hz"))
    check config.rate == "+10%"
    expect ConfigurationError:
      discard validateConfig(TtsConfig(voice: "bad", rate: "+0%",
        volume: "+0%", pitch: "+0Hz"))
    expect ConfigurationError:
      discard validateConfig(TtsConfig(voice: "en-US-EmmaMultilingualNeural",
        rate: "10%", volume: "+0%", pitch: "+0Hz"))

  test "natural split and XML entity safety":
    check splitTextByByteLength("hello world", 6) == @["hello", "world"]
    let entityText = "a".repeat(4090) & "&amp;rest"
    let entityChunks = splitTextByByteLength(entityText, 4094)
    check entityChunks.len == 2
    check entityChunks[0] == "a".repeat(4090)
    check entityChunks[1] == "&amp;rest"

  test "UTF-8 characters are never split":
    let chinese = "你好，世界。".repeat(1000)
    let chunks = splitTextByByteLength(chinese)
    check chunks.len > 1
    check chunks.join("") == chinese
    for chunk in chunks:
      check chunk.len <= 4096
    expect ConfigurationError:
      discard splitTextByByteLength("你", 2)
