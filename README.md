# Lumi

Ray-Ban Meta와 Gemini로 눈앞의 세상을 이해하는 개인 AI 비서.

## 현재 MVP

- 안경 마이크로 질문하고 안경 스피커로 답을 듣는 음성 Q&A
- 안경 카메라 사진 한 장을 Gemini에 보내는 장면 설명
- “기억해줘” 의도를 감지해 iPhone 로컬에 저장하는 음성 메모

## 실기기 시작 전 준비

1. `Secrets.xcconfig.example`을 복사해 `Secrets.xcconfig`을 만들고 `GEMINI_API_KEY`를 채웁니다.
2. iPhone에 Meta AI 앱과 Ray-Ban Meta 안경을 연결합니다.
3. Meta AI 앱에서 Developer Mode를 켭니다. 개발 모드에서는 `META_APP_ID = 0`으로 등록할 수 있습니다.
4. Xcode에서 iPhone 실기기를 선택해 앱을 실행한 뒤, Lumi의 **Meta AI에서 Lumi 연결** 버튼을 누릅니다.

`Secrets.xcconfig`은 Git에서 제외됩니다. 개인 개발용 직접 Gemini 호출은 빠른 검증을 위한 것이며, 배포 버전에서는 Gemini API 키를 앱에 넣지 않고 토큰 발급 서버를 사용해야 합니다.
