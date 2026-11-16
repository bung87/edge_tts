const
  DefaultVoice* = "en-US-EmmaMultilingualNeural"
  TrustedClientToken* = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
  BaseUrl* = "speech.platform.bing.com/consumer/speech/synthesize/readaloud"
  WssUrl* = "wss://" & BaseUrl & "/edge/v1?TrustedClientToken=" & TrustedClientToken
  VoiceListUrl* = "https://" & BaseUrl & "/voices/list?trustedclienttoken=" & TrustedClientToken
  ChromiumFullVersion* = "143.0.3650.75"
  ChromiumMajorVersion* = "143"
  SecMsGecVersion* = "2-" & ChromiumFullVersion
  UserAgent* = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " &
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/" & ChromiumMajorVersion &
    ".0.0.0 Safari/537.36 Edg/" & ChromiumMajorVersion & ".0.0.0"
  Origin* = "chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold"
  OutputFormat* = "audio-24khz-48kbitrate-mono-mp3"
  MaxTextBytes* = 4096
  TicksPerSecond* = 10_000_000'i64
  Mp3BitrateBps* = 48_000'i64
