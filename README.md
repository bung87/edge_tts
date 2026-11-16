# edge_tts

非官方 Microsoft Edge 文本转语音 Nim 客户端，使用 **Chronos** 异步运行时和 **websock** WebSocket 实现。支持流式返回 MP3 和 WebM/Opus 音频，默认格式为 `audio-24khz-48kbitrate-mono-mp3`。

## 安装

```bash
nimble install
```

作为其他 Nimble 项目的依赖：

```nim
requires "edge_tts"
```

直接依赖为 Nim >= 2.0.16、Chronos >= 4.4.1、websock 和 uuids。最低 Nim 版本由 websock 0.4.x 及 Chronos 4.4.1 的依赖要求共同决定。

## 语音列表

完整语音列表由服务动态返回。查询全部语音，或按地区前缀过滤：

```bash
nimble c -r examples/list_voices.nim
nimble c -r examples/list_voices.nim zh-CN
nimble c -r examples/list_voices.nim en-US
```

也可以在异步代码中调用 `listVoices()`：

```nim
let voices = await listVoices()
for voice in voices:
  echo voice.shortName, " | ", voice.locale, " | ", voice.gender
```

常用语音示例：

| ShortName | 性别 | 说明 |
|---|---|---|
| `en-US-EmmaMultilingualNeural` | 女 | 英语（美国）多语言语音，本包默认值 |
| `zh-CN-XiaoxiaoNeural` | 女 | 中文（中国大陆） |
| `zh-CN-XiaoyiNeural` | 女 | 中文（中国大陆） |
| `zh-CN-YunjianNeural` | 男 | 中文（中国大陆） |
| `zh-CN-YunxiNeural` | 男 | 中文（中国大陆） |
| `zh-CN-YunxiaNeural` | 男 | 中文（中国大陆） |
| `zh-CN-YunyangNeural` | 男 | 中文（中国大陆） |
| `zh-CN-liaoning-XiaobeiNeural` | 女 | 中文（东北官话） |
| `zh-CN-shaanxi-XiaoniNeural` | 女 | 中文（中原官话陕西话） |

可用语音可能随服务变化，以 `listVoices()` 的实时结果为准。

## 输出格式列表

通过 `outputFormat` 参数选择格式；默认值仍为 `audio-24khz-48kbitrate-mono-mp3`。`outputFormats()` 返回下表对应的 `OutputFormatInfo` 序列，包含 `name`、`contentType`、`extension` 和 `bytesPerSecond` 字段。

### 当前 Edge 端点支持的格式

| 格式标识 | 编码/容器 | 采样率 | 码率 | 扩展名 |
|---|---|---:|---:|---|
| `audio-24khz-48kbitrate-mono-mp3` | MP3，单声道 | 24 kHz | 48 kbps CBR | `.mp3` |
| `audio-24khz-96kbitrate-mono-mp3` | MP3，单声道 | 24 kHz | 96 kbps CBR | `.mp3` |
| `webm-24khz-16bit-mono-opus` | WebM / Opus，单声道 | 24 kHz | 可变码率 | `.webm` |

Azure Speech SDK 还定义了 WAV、PCM、Ogg 和其他 MP3 码率，但当前 Edge Read Aloud 端点会拒绝这些格式；本包的格式目录只列出该端点实际可用的三种格式。

使用示例：

```nim
let communicate = newCommunicate(
  "你好，世界！",
  voice = "zh-CN-XiaoxiaoNeural",
  outputFormat = "audio-24khz-96kbitrate-mono-mp3")
await communicate.save("speech.mp3", "speech.jsonl")

for format in outputFormats():
  echo format.name, " -> ", format.extension
```

输出文件扩展名由调用方指定，应与格式匹配。两种 MP3 按对应固定字节率补偿跨分片元数据偏移；WebM/Opus 使用边界元数据结束位置补偿。

## 保存音频

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
nimble c -r examples/synthesize.nim "高码率 MP3" speech.mp3 "" audio-24khz-96kbitrate-mono-mp3
nimble c -r examples/synthesize.nim "WebM Opus" speech.webm "" webm-24khz-16bit-mono-opus
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
- `outputFormat`：输出格式标识，默认为 `audio-24khz-48kbitrate-mono-mp3`；可选值见“输出格式列表”，也可通过 `outputFormats()` 查询。
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
nim c -r --path:src tests/all.nim
```

测试不访问网络，覆盖文本切分、协议解析、异常输入和固定时间的 `Sec-MS-GEC` v2 参考向量。

## 说明

这是非官方客户端，与 Microsoft 无关。服务端点和鉴权规则可能随时变化；请遵守适用的服务条款，并仅在你有权使用服务的场景中使用。
