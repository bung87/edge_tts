import std/os
import chronos
import edge_tts

proc main() {.async.} =
  let text = if paramCount() >= 1: paramStr(1)
             else: "你好，这是使用 Chronos 和 websock 编写的 Edge TTS 客户端。"
  let output = if paramCount() >= 2: paramStr(2) else: "output.mp3"
  let metadata = if paramCount() >= 3: paramStr(3) else: ""
  let outputFormat = if paramCount() >= 4: paramStr(4) else: DefaultOutputFormat
  let communicate = newCommunicate(text, voice = "zh-CN-XiaoxiaoNeural",
    boundary = BoundaryKind.WordBoundary, outputFormat = outputFormat)
  await communicate.save(output, metadata)
  echo "Saved audio to ", output
  if metadata.len > 0:
    echo "Saved metadata to ", metadata

waitFor(main())
