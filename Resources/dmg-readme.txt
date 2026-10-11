QuotaBar — Claude · Codex · Gemini · Grok 구독 사용 한도를 메뉴바에서 확인

■ 설치
1. QuotaBar 를 "Applications" 폴더로 끌어다 놓습니다.
2. 응용 프로그램 폴더에서 QuotaBar 를 엽니다. 메뉴바에 아이콘이 나타납니다.

"확인되지 않은 개발자" 또는 "손상되었습니다" 경고가 뜨면
(Apple 공증을 받지 않은 앱이라 처음 한 번만 필요합니다)
- 시스템 설정 > 개인정보 보호 및 보안 > 아래쪽 "그래도 열기" 를 누르거나,
- 터미널에서 다음을 실행한 뒤 다시 엽니다.
    xattr -dr com.apple.quarantine /Applications/QuotaBar.app

■ 내 계정 연동
따로 입력할 것은 없습니다. 이 Mac 에서 각 서비스의 CLI 에 로그인해 두면
QuotaBar 가 그 로그인 정보를 읽어 "내 계정"의 사용량을 보여 줍니다.

  Claude  : Claude Code 에 로그인 (터미널에서 claude)
  Codex   : Codex CLI 에 ChatGPT 계정으로 로그인 (codex login)
  Gemini  : 개인 구독은 Antigravity CLI (agy), Workspace·교육 계정은 Gemini CLI (gemini)
  Grok    : Grok CLI 에 로그인 (grok login)

- 로그인이 안 된 서비스는 타일에 "로그인" 버튼이 보입니다. 누르면 터미널에서 로그인 명령을 실행합니다.
- 쓰지 않는 서비스는 타일의 "숨기기" 를 누르세요. 설정(⋯ > 설정…)의 "표시할 서비스"에서 다시 켤 수 있습니다.
- 처음 조회할 때 macOS 가 키체인 접근을 물어볼 수 있습니다. CLI 가 저장한 로그인 정보를 읽기 위한 것이며
  "항상 허용"을 누르면 다시 묻지 않습니다.

■ 개인정보
- 로그인 정보는 이 Mac 안에서만 읽고, 각 서비스(Anthropic, OpenAI, Google, xAI)의 서버에
  사용량을 물어볼 때만 씁니다. 그 밖의 서버로는 아무것도 보내지 않습니다.
- CLI 의 로그인 파일은 수정하지 않습니다.
- 설정은 ~/.config/quotabar/.env 에 저장됩니다 (본인만 읽을 수 있는 권한).

■ 알아 둘 점
- 각 서비스가 공식 문서로 제공하지 않는 조회 경로를 쓰는 부분이 있어, 서비스가 바뀌면 일부가 잠시 안 보일 수 있습니다.
- 사용량은 기본 10분마다 갱신합니다. 너무 자주 조회하면 서비스 쪽에서 조회를 잠시 제한할 수 있습니다.
