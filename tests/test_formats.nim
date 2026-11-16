import std/unittest
import edge_tts/[constants, formats, text, types]

suite "output formats":
  test "format catalog and fixed byte rates":
    check outputFormats().len == 3
    let defaultFormat = getOutputFormat(DefaultOutputFormat)
    check defaultFormat.contentType == "audio/mpeg"
    check defaultFormat.extension == ".mp3"
    check defaultFormat.bytesPerSecond == 6_000
    check getOutputFormat("audio-24khz-96kbitrate-mono-mp3").bytesPerSecond == 12_000
    check getOutputFormat("webm-24khz-16bit-mono-opus").bytesPerSecond == 0

  test "content types and aliases":
    check getOutputFormat("webm-24khz-16bit-mono-opus").acceptsContentType("audio/webm; codecs=opus")
    check not getOutputFormat(DefaultOutputFormat).acceptsContentType("video/mp4")

  test "configuration validation":
    var config = TtsConfig(voice: "en-US-EmmaMultilingualNeural",
      rate: "+0%", volume: "+0%", pitch: "+0Hz")
    check validateConfig(config).outputFormat == DefaultOutputFormat
    config.outputFormat = "webm-24khz-16bit-mono-opus"
    check validateConfig(config).outputFormat == config.outputFormat
    config.outputFormat = "riff-24khz-16bit-mono-pcm"
    expect ConfigurationError:
      discard validateConfig(config)
    config.outputFormat = "not-a-format"
    expect ConfigurationError:
      discard validateConfig(config)
