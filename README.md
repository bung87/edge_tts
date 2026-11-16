# edge_tts

非官方 Microsoft Edge 文本转语音 Nim 客户端，使用 **Chronos** 异步运行时和 **websock** WebSocket 实现。音频以 `audio-24khz-48kbitrate-mono-mp3` 格式流式返回。

## 安装

```bash
nimble install
```

作为其他 Nimble 项目的依赖：

```nim
requires "edge_tts"
```

直接依赖为 Nim >= 2.0.16、Chronos >= 4.4.1、websock 和 uuids。最低 Nim 版本由 websock 0.4.x 及 Chronos 4.4.1 的依赖要求共同决定。

## 保存 MP3

```nim
import chronos
import edge_tts

proc main() {.async.} =
  let communicate = newCommunicate(
    "你好，世界！",
    voice = "zh-CN-XiaoxiaoNeural",
    rate = "+0%",
    volume = "+0%",
    pitch = "+0Hz",
    boundary = BoundaryKind.WordBoundary)
  await communicate.save("speech.mp3", "speech.jsonl")

waitFor(main())
```

第二个路径可省略；提供时，词/句边界以 JSON Lines 写入。`offset` 和 `duration` 单位为 100 纳秒。

也可以运行仓库示例：

```bash
nimble c -r examples/synthesize.nim "要合成的文本" speech.mp3 speech.jsonl
nimble c -r examples/list_voices.nim zh-CN
```

## 流式处理

```nim
import chronos
import edge_tts

var audioBytes = 0

proc onChunk(chunk: TtsChunk) {.closure, gcsafe.} =
  case chunk.kind
  of Audio:
    audioBytes += chunk.data.len
    # 在这里写入文件、网络流或播放器缓冲区。
  of WordBoundary, SentenceBoundary:
    echo chunk.text, " @ ", chunk.offset

proc main() {.async.} =
  let communicate = newCommunicate("Streaming text")
  await communicate.stream(onChunk)

waitFor(main())
```

回调按服务到达顺序同步执行，下一帧只有在回调返回后才读取。一个 `Communicate` 实例只能调用一次 `stream` 或 `save`。长文本会按 UTF-8 和 XML 实体安全边界拆成多个 WebSocket turn，音频不会被整体缓存在内存中。

## 参数和选项

- `voice`：短名称，例如 `en-US-EmmaMultilingualNeural`；也接受完整 Microsoft Server Speech 名称。
- `rate`、`volume`：`+0%`、`-10%`、`+25%` 等带符号百分比。
- `pitch`：`+0Hz`、`-2Hz` 等带符号赫兹值。
- `boundary`：`SentenceBoundary`（默认）或 `WordBoundary`。
- `ClientOptions`：默认连接超时 10 秒、单帧接收超时 60 秒；`clockSkewSeconds` 可修正本机时钟偏差。

```nim
var options = defaultClientOptions()
options.connectTimeout = 20.seconds
options.receiveTimeout = 90.seconds
let communicate = newCommunicate("Text", options = options)
```

`listVoices()` 返回 `Future[seq[Voice]]`，包含名称、地区、性别及语音标签。TLS 证书和主机名验证默认开启。当前 API 不自动读取 HTTP(S)_PROXY，也未实现 WebSocket CONNECT 代理隧道。

## 测试

```bash
nimble test
```

测试不访问网络，覆盖文本切分、协议解析、异常输入和固定时间的 `Sec-MS-GEC` v2 参考向量。

## 说明

这是非官方客户端，与 Microsoft 无关。服务端点和鉴权规则可能随时变化；请遵守适用的服务条款，并仅在你有权使用服务的场景中使用。
