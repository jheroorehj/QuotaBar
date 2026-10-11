#!/usr/bin/env bash
# .env.example 내용을 Sources/QuotaBarCore/Config/EnvTemplate.swift 로 복사한다.
set -euo pipefail
cd "$(dirname "$0")/.."

{
  printf '// 이 파일은 QuotaBar/.env.example 과 내용이 같아야 한다. (EnvTemplateTests 가 확인)\n'
  printf '// .env.example 을 수정했다면 scripts/sync-env-template.sh 를 실행한다.\n\n'
  printf '/// 설정 파일 템플릿. "설정 파일 열기" 시 파일이 없으면 이 내용으로 만든다.\n'
  printf 'public enum EnvTemplate {\n'
  printf '    public static let contents = #"""\n'
  cat .env.example
  printf '"""#\n}\n'
} > Sources/QuotaBarCore/Config/EnvTemplate.swift

echo "EnvTemplate.swift 갱신 완료"
