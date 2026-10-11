---
version: alpha
name: Apple Liquid Glass for SwiftUI iOS
description: Apple의 동적 재질과 시스템 컴포넌트를 우선하는 SwiftUI iOS UI/UX 디자인 지침.
omitted:
  - section: colors
    reason: 런타임에서 변하는 Apple semantic colors를 고정 CSS 색상으로 치환하지 않는다. Colors의 SwiftUI 매핑을 사용한다.
  - section: typography
    reason: Dynamic Type을 유지하기 위해 고정 fontSize 토큰을 생략한다. Typography의 Font.TextStyle 매핑을 사용한다.
  - section: rounded
    reason: 시스템 컨트롤의 곡률과 Capsule·Circle을 사용한다. 사용자 정의 콘텐츠의 곡률은 Shapes에서 별도로 규정한다.
spacing:
  xs: 4
  sm: 8
  md: 12
  lg: 16
  xl: 24
  xxl: 32
components:
  custom-content-panel:
    padding: "{spacing.lg}"
  custom-control-label:
    padding: "{spacing.sm}"
---

# SwiftUI / iOS Liquid Glass Design System

## Overview

읽기 쉬운 콘텐츠, 익숙한 조작, 절제된 시각적 강조를 기본 톤으로 삼는다. Liquid Glass는 콘텐츠 위의 내비게이션과 조작 영역에 사용하며, 화면 전체를 투명하게 만드는 장식으로 사용하지 않는다.

이 문서는 Google Labs의 공개 DESIGN.md **alpha** 명세에 따라 YAML front matter와 정해진 순서의 Markdown 섹션을 구성한다. Apple이 제정한 DESIGN.md 양식이나 확정된 범산업 표준을 의미하지 않는다. 접근성·SwiftUI 구현·검증·출처는 명세가 허용하는 추가 섹션이다. [F1]

대상은 SwiftUI로 구현하는 iOS 앱이며 iPadOS 적응형 화면을 포함한다. Liquid Glass API가 도입된 iOS/iPadOS 26.0을 기능 분기 기준으로 사용한다. 프로젝트의 최소 지원 OS는 별도로 유지한다. macOS·watchOS·visionOS에 이 문서의 크기와 내비게이션 규칙을 그대로 적용하지 않는다.

프로젝트 소스·화면·브랜드 팔레트가 제공되지 않았으므로, 특정 앱을 분석한 결과가 아닌 재사용 가능한 기본 정책이다. 기존의 검증된 브랜드 색과 정보 구조를 유지하고 이 문서의 역할에 연결한다. 규칙을 적용하면서 임의의 브랜드 색이나 기능을 추가하지 않는다.

Apple 공식 지침과 API 동작에는 출처를 붙인다. 간격 스케일, 사용자 정의 카드 반경, 주요 행동의 강조 수 등은 이 문서가 채택한 프로젝트 기본값이며 Apple의 고정 규격이 아니다. 문서 확인일은 2026-10-08이다.

YAML에는 프로젝트가 고정할 수 있는 값만 기록한다. `spacing`의 숫자는 이 iOS 프로젝트에서 **논리적 포인트(pt)** 로 해석하며 물리 픽셀로 변환하지 않는다. 이는 DESIGN.md가 허용하는 숫자형 spacing을 사용하는 프로젝트 매핑이다. 색·타이포그래피·시스템 곡률은 `omitted`로 의도적 생략을 선언하고 아래의 네이티브 API를 사용한다. CSS 색상 자리에 `Color.primary` 같은 문자열을 넣거나, 명세의 Dimension에 지원되지 않는 `pt` 단위를 끼워 넣지 않는다. [F1]

UI 문구는 짧고 구체적으로 쓴다. 버튼은 ‘확인’보다 실제 결과를 나타내는 ‘저장’, ‘다시 시도’, ‘필터 적용’을 우선한다. 오류는 현재 상황과 사용자가 할 수 있는 다음 행동을 설명한다. 유리·블러·렌더링 같은 구현 용어는 실제 사용자 결정에 필요한 경우에만 노출한다.

## Colors

시스템 색과 전경 스타일을 역할에 따라 사용한다. 밝은 화면에서 추출한 HEX를 다크 모드에도 재사용하지 않는다. 브랜드 색이 있다면 기존 `AccentColor`를 연결하고, 직접 정의한 색에는 밝은 모드·어두운 모드·대비 증가 변형을 마련한다. [A8]

| 역할 | SwiftUI 표현 | 적용 범위 |
| --- | --- | --- |
| 주요 텍스트·아이콘 | `.foregroundStyle(.primary)` | 제목, 본문, 중요한 값 |
| 보조 텍스트 | `.foregroundStyle(.secondary)` | 설명, 시간, 부가 정보 |
| 낮은 우선순위 정보 | `.foregroundStyle(.tertiary)` | 없어도 과업 수행이 가능한 부가 표시 |
| 일반 화면 배경 | `Color(uiColor: .systemBackground)` | 일반 콘텐츠 화면 |
| 그룹형 화면 배경 | `Color(uiColor: .systemGroupedBackground)` | 설정·양식의 배경 |
| 그룹 안의 콘텐츠 표면 | `Color(uiColor: .secondarySystemGroupedBackground)` | 사용자 정의 그룹 카드 |
| 일반 화면의 보조 표면 | `Color(uiColor: .secondarySystemBackground)` | 사용자 정의 보조 패널 |
| 필요한 구분선 | `Color(uiColor: .separator)` | 시스템 구분선으로 충분하지 않은 경우 |
| 주요 행동·선택 강조 | `.tint(.accentColor)` | 기존 브랜드 또는 시스템 accent 사용 |
| 파괴적 행동 | `Button(role: .destructive)` | 삭제 등 되돌리기 어려운 동작 |

전경의 `.primary`·`.secondary`는 `ShapeStyle`의 의미 기반 계층이다. 모든 글자를 흰색으로 고정하거나 텍스트 전체의 opacity를 낮춰 이 계층을 모방하지 않는다. 특히 유리 위 텍스트에는 배경 변화에 반응하는 시스템 처리를 유지한다. [A8]

프로젝트 기본 정책으로 한 화면의 가장 중요한 행동에 우선적으로 accent를 배정한다. 일반 콘텐츠 카드, 모든 툴바 버튼, 유리 표면 전체를 브랜드 색으로 채우지 않는다. `.tint`와 `Glass.tint(_:)`는 강조를 위한 색조이며 유리의 고정 투명도 설정이 아니다.

오류·성공·경고·선택은 색과 함께 문구 또는 기호로 나타낸다. ‘빨간색이면 오류’처럼 색에만 의미를 맡기지 않는다. 차트와 상태 표시도 같은 규칙을 따른다. [A10]

## Typography

시스템 서체와 Dynamic Type을 사용한다. 한국어·영어가 섞인 화면도 시스템의 문자별 폰트 선택을 유지하며 특정 SF 폰트 파일 이름을 하드코딩하지 않는다. 크기·줄 높이·자간을 화면마다 수동 조절하기 전에 아래의 의미 기반 스타일을 선택한다. [A9]

| 역할 | SwiftUI 스타일 | 사용 규칙 |
| --- | --- | --- |
| 화면 제목 | `.navigationTitle(...)` | 표준 내비게이션 제목을 우선 |
| 콘텐츠의 큰 제목 | `.font(.largeTitle)` | 랜딩 또는 독립적인 콘텐츠 제목 |
| 주요 섹션 제목 | `.font(.title2)` | 본문보다 한 단계 높은 구조 |
| 작은 섹션·컨트롤 제목 | `.font(.headline)` | 짧은 제목과 명확한 행동 라벨 |
| 본문·입력 내용 | `.font(.body)` | 읽거나 편집해야 하는 주요 내용 |
| 짧은 보조 설명 | `.font(.callout)` 또는 `.font(.subheadline)` | 본문의 이해를 돕는 정보 |
| 주석·메타데이터 | `.font(.footnote)` 또는 `.font(.caption)` | 필수 본문을 작게 압축하는 용도로 사용 금지 |
| 실시간 수치 | 적절한 텍스트 스타일 + `.monospacedDigit()` | 수치 변경 시 자리 폭의 흔들림 완화 |

기본 굵기와 강조 굵기로 위계를 만든다. 숫자 하나를 크게 보이게 하려고 화면 전체에 굵은 글자를 사용하지 않는다. 위 표의 역할 배정은 프로젝트 정책이며 Apple이 모든 화면에 강제하는 분류는 아니다.

Dynamic Type이 커지면 줄바꿈과 세로 배치를 허용한다. 설명이 있는 버튼이나 행에 고정 높이를 주지 않고, 정보가 잘리는 문제를 `.minimumScaleFactor`나 Dynamic Type 범위 제한으로 덮지 않는다. 아이콘도 텍스트와 함께 읽기 쉬운 크기로 변해야 한다. [A9]

## Layout

`NavigationStack`, `TabView`, `NavigationSplitView`, `List`, `Form`, `.toolbar`, `.sheet` 등 표준 구조를 먼저 선택한다. 시스템이 담당하는 여백·컨트롤 크기·safe area를 보존한다. 콘텐츠는 가장 넓은 영역을 사용하고, 탐색과 조작은 그 위에서 일관된 위치와 묶음을 유지한다. [A1]

사용자 정의 영역에만 YAML spacing을 적용한다. 다음 값은 프로젝트 기본값이며 시스템 `List` 행 간격이나 툴바 배치를 강제로 덮어쓰는 기준이 아니다.

| 토큰 | 값 | 사용자 정의 영역의 기본 용도 |
| --- | --- | --- |
| `spacing.xs` | 4 pt | 긴밀한 텍스트·보조 정보 사이 |
| `spacing.sm` | 8 pt | 라벨 주변의 작은 여백 |
| `spacing.md` | 12 pt | 관련된 작은 요소 사이 |
| `spacing.lg` | 16 pt | 콘텐츠 패널 내부 및 일반적인 그룹 간격 |
| `spacing.xl` | 24 pt | 별도 섹션 사이 |
| `spacing.xxl` | 32 pt | 큰 내용 묶음 사이 |

사진·배경은 필요하면 가장자리까지 확장하되 읽기·입력·조작 요소는 safe area를 존중한다. 하단 조작부가 콘텐츠와 키보드를 덮지 않도록 `.safeAreaInset` 같은 레이아웃 수단을 검토한다. 단순한 `ZStack` 오버레이만 추가한 뒤 마지막 행을 가리는 구성을 허용하지 않는다.

iPadOS와 큰 글자 환경은 실제 가용 폭에 따라 재배치한다. 특정 iPhone 해상도를 기준으로 화면 폭·높이를 고정하지 않는다. 보조 정보가 밀리면 우선 세로로 쌓고, 탐색 구조에 적합하면 `NavigationSplitView`를 사용한다.

이 프로젝트는 사용자 정의 터치 컨트롤의 목표 영역을 최소 44 × 44 pt로 둔다. 이는 HIG의 iOS/iPadOS 기본 컨트롤 크기를 채택한 프로젝트 기준이다. 이를 Apple이 모든 컨트롤에 예외 없이 요구하는 최소 크기라고 설명하지 않는다. 보이는 아이콘이 작더라도 실제 터치 영역과 주변 간격은 확보한다. [A10]

## Elevation & Depth

깊이는 콘텐츠, 조작, 모달의 관계를 설명해야 한다. 카드마다 그림자나 유리 효과를 추가해 깊이를 장식하지 않는다. 시스템이 제공하는 광학 효과·그림자·스크롤 경계 처리를 우선한다. [A7]

| 영역·상황 | 기본 재질 | 적용 기준 |
| --- | --- | --- |
| 본문, 목록, 입력 양식, 일반 카드 | 의미 기반 배경색 | 읽고 비교하는 콘텐츠 표면 |
| 콘텐츠 내부에서 필요한 반투명 구분 | `Material`의 `.regularMaterial` 등 | 콘텐츠용 표준 재질이며 Liquid Glass와 별개 |
| 탭 바·툴바·내비게이션 | 시스템 기본 외형 | 추가 `glassEffect`나 사용자 정의 배경을 겹치지 않음 |
| 사용자 정의 부유 컨트롤 | `Glass.regular` | 기본 선택; 배경 가독성과 조작 구분 확보 |
| 사진·영상 위의 제한된 컨트롤 | `Glass.clear` | 콘텐츠 가시성을 우선하며 대비가 검증된 경우 |
| 시트·팝오버·메뉴 | 네이티브 presentation | 크기와 상태에 따른 시스템 재질 변화 유지 |

`Glass.regular`는 배경의 밝기와 흐림을 조절하는 Liquid Glass이고, `Material.regular`는 콘텐츠 구분에 쓰는 표준 재질이다. 이름의 `regular`가 같아도 동일한 효과가 아니다. 일반 카드에는 Liquid Glass를 사용하지 않는다. 시스템 슬라이더·토글의 일부가 조작 중 유리로 변하는 기본 동작은 유지한다. [A2]

### 투명도와 가독성

Liquid Glass의 전역 opacity, blur radius, refraction 수치를 프로젝트 상수로 정의하지 않는다. 공개 SwiftUI 재질 API와 시스템의 환경 반응을 사용한다. `.opacity(0.7)`를 유리 컨테이너에 적용하면 자식 텍스트·아이콘까지 흐려질 수 있으므로 유리 투명도 조절 방법으로 사용하지 않는다.

`Glass.regular`를 기본으로 선택한다. `Glass.clear`는 사진·영상처럼 시각적으로 풍부한 배경 위의 컨트롤에 제한한다. 텍스트가 많거나 배경에 따라 읽기 어려워지는 패널에는 regular가 적합하다. 밝은 콘텐츠 위 clear에는 **뒤쪽에 검은색 35% 불투명도 dimming layer를 고려**할 수 있다. 이는 조건부 가이드이며 유리 자체의 opacity나 화면 전체의 어둡기 토큰이 아니다. 배경이 충분히 어둡거나 AVKit이 이미 dimming을 제공하면 중복 적용하지 않는다. [A2][A12]

가독성이 부족하면 clear 선택을 재검토하고, 콘텐츠용 패널이면 불투명 배경으로 전환한다. 효과를 유지하려고 텍스트 크기를 줄이거나 필수 정보를 없애지 않는다. 프로젝트는 clear 사용 위치마다 밝은·어두운·복잡한 배경에서 대비를 확인한다.

### 중첩과 움직임

하나의 버튼을 `.glass` 스타일로 만든 뒤 그 위에 `.glassEffect()`를 추가하지 않는다. 유리 컨트롤을 다시 유리 카드로 감싸지 않는다. `GlassEffectContainer`는 여러 효과의 렌더링과 결합을 조정하는 컨테이너이며 그 자체에 별도 유리 배경을 추가하라는 의미가 아니다. [A3][A11]

`GlassEffectContainer(spacing:)`는 자식의 레이아웃 간격을 정하지 않는다. 가까운 유리 도형이 합쳐지는 거리에 관여하며 `HStack(spacing:)`와 역할이 다르다. 기본 정책은 서로 다른 행동의 경계가 안정적으로 유지되도록 하는 것이다. 도형 결합이 행동 관계를 명확하게 설명할 때만 의도적으로 사용한다. [A11]

모션은 누른 곳과 나타나는 결과의 관계를 설명하는 데 쓴다. 표준 전환을 유지하고 장식적 반복 애니메이션을 넣지 않는다. 사용자 정의 morphing이 필요하면 컨테이너와 `glassEffectID(_:in:)`를 검토하며, Reduce Motion 환경의 대체 동작을 함께 정의한다. [A3][A13]

## Shapes

표준 컨트롤의 곡률은 시스템에 맡긴다. 독립적인 짧은 부유 컨트롤은 `Capsule`, 아이콘 중심의 원형 컨트롤은 `Circle`을 우선 검토한다. 폰 화면 가장자리와 둥근 요소가 맞물릴 때 충분한 여백을 두고, 중첩된 도형의 곡률은 서로 동심 관계를 이루도록 구성한다. [A7]

프로젝트 기본값으로 사용자 정의 **일반 콘텐츠 카드**가 꼭 필요할 때는 `RoundedRectangle(cornerRadius: 16, style: .continuous)`를 출발점으로 사용한다. 16 pt는 Apple의 Liquid Glass 규격이 아니다. `List`·`Form`·시트·툴바의 시스템 곡률을 이 값으로 덮어쓰지 않는다.

유리 효과 뒤에 별도 clipping을 추가해 그림자나 가장자리 광학 효과를 자르지 않는다. 사용자 정의 효과의 모양은 우선 `glassEffect(_:in:)`의 `in:` 인자로 전달한다. 콘텐츠 이미지의 마스크와 부유 컨트롤의 재질 모양은 각각의 역할에 맞게 다룬다. [A4]

## Components

표준 컴포넌트는 동작과 접근성 의미까지 함께 선택한다. 같은 모양을 만들기 위해 `Text`와 `onTapGesture`로 `Button`을 대체하지 않는다.

| 컴포넌트 | 우선 구현 | 프로젝트 규칙 |
| --- | --- | --- |
| 화면 탐색 | `NavigationStack`, `NavigationLink` | 뒤로 가기·제목·스와이프 동작 유지 |
| 최상위 목적지 | `TabView` | 목적지 이동에 사용; 실행 버튼을 탭으로 위장하지 않음 |
| 도구 모음 | `.toolbar` | 관련 행동을 묶고 중요 행동의 위치 유지 |
| 강조할 부유 버튼 | `.buttonStyle(.glassProminent)` | 조작 계층의 주요 행동에 제한 |
| 일반 부유 버튼 | `.buttonStyle(.glass)` | 보조 행동; 배경 효과를 추가로 겹치지 않음 |
| 콘텐츠 내부 버튼 | 문맥에 맞는 기본·`.bordered`·`.borderedProminent` | 모든 본문 행동을 부유 유리 버튼으로 바꾸지 않음 |
| 목록·설정·입력 | `List`, `Form`, `Section`, `TextField` | 읽기·입력 표면의 가독성을 우선 |
| 선택·값 조절 | `Picker`, `Toggle`, `Slider` | 시스템 상태와 조작 피드백 유지 |
| 검색 | `.searchable` 및 적절한 search 역할 | 검색과 키보드의 플랫폼 동작 유지 |
| 임시 과업·세부 옵션 | `.sheet`, `.popover`, `Menu`, `.confirmationDialog` | 출발 컨트롤과 결과의 관계 유지 |
| 진행·빈 화면 | `ProgressView`, 지원 OS의 `ContentUnavailableView` | 진행 여부와 가능한 다음 행동 제시 |

`.glass`와 `.glassProminent`는 iOS/iPadOS 26.0 이상에서 사용한다. 버튼 스타일은 기본적인 상호작용을 함께 제공한다. 직접 만든 형태가 반드시 필요할 때만 `glassEffect`와 `interactive(_:)`를 사용한다. `interactive()` 자체는 버튼 동작이나 접근성 역할을 만드는 API가 아니다. [A5][A6][A3]

툴바에는 익숙한 SF Symbols를 사용하고 아이콘에 접근 가능한 이름을 제공한다. 같은 배경을 공유하는 묶음에서 독립적인 텍스트 버튼과 아이콘 버튼이 하나의 행동처럼 보이지 않게 분리한다. 시스템 바에 임의의 그라데이션·테두리·불투명 배경을 추가하기 전에 표준 grouping과 scroll edge effect로 해결되는지 확인한다. [A1][A7]

시트의 재질을 항상 반투명으로 고정하지 않는다. 크기와 상태에 따라 더 불투명해지는 시스템 동작을 유지한다. 시트 내부 모서리, 하단 조작부, 키보드가 나타난 상태의 입력 필드가 잘리지 않도록 확인한다. [A1]

| 상태 | 표현 | 동작 규칙 |
| --- | --- | --- |
| 기본 | 시스템 기본 스타일 | 실행 가능한 행동을 구별할 수 있어야 함 |
| 눌림 | 네이티브 버튼 피드백 | 별도 축소·번쩍임 효과를 중복 적용하지 않음 |
| 선택 | 선택 표시 + 필요한 tint | 색을 구별하지 못해도 현재 선택이 드러나야 함 |
| 비활성 | `.disabled(true)` | 낮은 opacity만으로 비활성을 흉내 내지 않음 |
| 로딩 | `ProgressView` + 진행 문구 | 중복 실행 방지; 기존 내용과 레이아웃을 가능한 한 유지 |
| 실패 | 구체적인 오류 + 재시도·수정 경로 | 유리 색 변화만으로 오류를 알리지 않음 |
| 빈 상태 | 상황 설명 + 다음 행동 | 데이터 없음과 불러오기 실패를 구분 |

위 상태 표현은 프로젝트 기본 정책이다. 비동기 작업을 표현할 때 실제 완료 여부와 화면의 성공 표시가 일치해야 한다.

## Do's and Don'ts

- 시스템 컴포넌트로 먼저 구현하고 실제로 부족한 부분만 사용자 정의한다.
- 콘텐츠를 읽고 비교하는 영역은 안정적인 배경과 위계를 유지한다.
- 유리 효과는 필요한 조작·탐색 계층에 제한한다.
- 색·폰트·크기·모션은 시스템 설정과 함께 검증한다.
- 모든 카드, 행, 입력 필드에 `glassEffect()`를 일괄 적용하지 않는다.
- blur와 흰색 반투명 사각형을 조합한 결과를 네이티브 Liquid Glass라고 부르지 않는다.
- 유리 효과 위에 유리 효과·광택 테두리·강한 그림자를 중복하지 않는다.
- `.clear`와 35% dimming을 앱 전체의 기본 스타일로 사용하지 않는다.
- 읽기 어려운 상태를 브랜드 감성이나 투명감 때문에 유지하지 않는다.
- 존재하지 않는 opacity·blur·refraction 설정 API를 만들어 구현 지시하지 않는다.

## Accessibility

표준 컴포넌트의 자동 적응을 유지하되, 사용자 정의 재질과 색·애니메이션은 직접 검증한다. 플랫폼이 제공하는 Liquid Glass 외형 설정을 앱에서 우회하거나 특정 외형으로 강제하지 않는다. [A1]

| 환경·설정 | 필요한 결과 | SwiftUI 확인점 |
| --- | --- | --- |
| Reduce Transparency | 흐린 배경에 의존하지 않고 경계와 글자가 읽힘 | `accessibilityReduceTransparency`; 사용자 정의 배경에는 불투명 대안 |
| Increase Contrast | 중요한 글자와 컨트롤의 대비 확보 | `colorSchemeContrast`; 시스템 색 또는 high contrast asset |
| Reduce Motion | 불필요한 크기 변화·morphing·반복 움직임 축소 | `accessibilityReduceMotion`; 직접 추가한 애니메이션의 대체 동작 |
| Differentiate Without Color | 선택·오류·성공이 색 없이도 식별됨 | `accessibilityDifferentiateWithoutColor`; 기호·문구 병행 |
| Dynamic Type·Bold Text | 주요 정보와 행동이 잘리지 않음 | 시스템 TextStyle; 줄바꿈·세로 재배치 |
| VoiceOver·Voice Control | 조작 이름·상태·순서를 이해할 수 있음 | 네이티브 컨트롤 의미, 필요한 label·value·hint |

본문 수준의 일반 텍스트는 4.5:1 이상의 대비를 프로젝트 검증 기준으로 삼는다. 큰 글자의 완화 기준을 적용할 때는 실제 크기와 굵기에 해당하는 HIG/WCAG 조건을 따르며, 모든 제목에 일괄 3:1을 적용하지 않는다. 유리 위 텍스트는 고정된 색 두 개만 비교해서 통과했다고 판단하지 않고 실제 합성 결과를 여러 배경에서 확인한다. [A10]

접근성 설정 때문에 유리가 더 불투명해지거나 모션이 줄어든 결과도 정상적인 디자인이다. 아래 예제의 사용자 정의 컨트롤은 Reduce Transparency에서 불투명 배경을 사용하는 프로젝트 정책을 명시적으로 구현한다. 네이티브 유리 버튼을 모두 직접 재구현할 필요는 없다. [A14]

## SwiftUI Implementation

### 적용 순서

1. 현재 프로젝트의 deployment target과 SDK를 확인하고, 지원 가능한 SDK로 기존 화면을 실행해 시스템 컴포넌트의 기본 변화를 확인한다.
2. 탐색·도구 모음·시트에 추가한 배경·blur·테두리를 검토하고 네이티브 외형을 가리는 장식을 정리한다.
3. 콘텐츠와 조작 영역을 구분한 뒤 색·타이포그래피를 이 문서의 의미 기반 역할에 연결한다.
4. 표준 구조로 해결되지 않는 부유 컨트롤에만 Liquid Glass를 추가하고 OS availability를 처리한다.
5. 접근성·화면 크기·입력·오류 상태를 검증하고 실제 기기에서 가독성과 성능을 확인한다.

### 시스템 버튼 우선

다음 예제는 iOS 16 이상을 컨텍스트로 작성했다. 이를 붙여 넣기 위해 기존 deployment target을 임의로 변경하지 않는다. iOS 26 SDK 이상으로 빌드하고, 26 미만에서는 기존 네이티브 버튼 스타일을 사용한다. Liquid Glass를 예전 OS에서 흉내 내기 위한 렌더러를 추가하지 않는다. [A5][A6]

```swift
import SwiftUI

@available(iOS 16.0, *)
struct PrimaryFloatingAction: View {
    let title: LocalizedStringKey
    let action: () -> Void
    var isEnabled = true

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                Button(title, action: action)
                    .buttonStyle(.glassProminent)
            } else {
                Button(title, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.large)
        .disabled(!isEnabled)
    }
}
```

이 컴포넌트는 화면의 조작 계층에 놓는 주요 행동을 위한 예제다. 표준 툴바 안의 버튼에는 우선 툴바가 제공하는 외형을 사용한다. 앱에 지정된 tint를 상속하며 임의의 새 브랜드 색을 만들지 않는다.

### 사용자 정의 컨트롤이 필요한 경우

아래 예제는 명시적인 터치 영역과 사용자 정의 재질 fallback을 보여준다. 일반 버튼은 위의 네이티브 스타일을 우선한다. padding과 크기를 정한 다음 컨트롤에 재질을 적용한다. `.regularMaterial` fallback은 표준 반투명 재질이며 Liquid Glass와 동등한 효과가 아니다. [A4][A14]

```swift
import SwiftUI

@available(iOS 16.0, *)
private struct FloatingControlSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(
                Color(uiColor: .secondarySystemBackground),
                in: Capsule()
            )
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}

@available(iOS 16.0, *)
struct FloatingFilterAction: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("필터", systemImage: "line.3.horizontal.decrease")
                .font(.body)
                .foregroundStyle(.primary)
                .padding(.horizontal, 16) // spacing.lg
                .padding(.vertical, 8)    // spacing.sm
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .modifier(FloatingControlSurface())
    }
}
```

커스텀 유리 컨트롤이 가까이 여러 개 배치되면 하나의 적절한 `GlassEffectContainer`에서 관리한다. 목록 행마다 컨테이너를 새로 만들지 않는다. 상위 계층에도 효과를 추가해 이중 유리 표면을 만들지 않는다. [A11]

사용자 정의 전환은 `@Environment(\.accessibilityReduceMotion)` 값을 확인한다. 예를 들어 상태 변경을 `withAnimation(reduceMotion ? nil : .default) { ... }`로 수행할 수 있다. 이 코드는 직접 추가한 애니메이션의 예이며 시스템 전환 전체를 꺼야 한다는 지침은 아니다. [A13]

### 프로젝트와 코딩 에이전트 연결

이 파일은 프로젝트 루트의 `DESIGN.md`로 둔다. 파일을 배치하는 것만으로 모든 도구가 자동 적용한다고 가정하지 않는다. 사용하는 도구의 실제 프로젝트 지침 파일에 다음 취지의 참조를 추가한다. 기존 지침 파일 전체를 이 문장으로 교체하지 않는다.

```text
UI를 생성하거나 변경하기 전에 루트의 DESIGN.md를 읽는다.
SwiftUI의 시스템 컴포넌트, 의미 기반 색, Dynamic Type을 우선한다.
DESIGN.md의 고정 프로젝트 값과 Apple이 런타임에 결정하는 값을 구분한다.
Liquid Glass는 OS availability와 접근성 대안을 함께 구현한다.
프로젝트의 기존 브랜드 자산과 지원 OS를 임의로 변경하지 않는다.
```

## Validation

| 검증 축 | 확인 조건 | 통과 기준 |
| --- | --- | --- |
| 구조 | 콘텐츠·탐색·조작·모달 | 각 영역의 역할과 현재 위치가 명확함 |
| 재질 | 기본·clear 사용 지점·중첩 | 콘텐츠에 무분별한 유리가 없고 clear의 근거가 있음 |
| 배경 | 밝음·어두움·사진·복잡한 스크롤 콘텐츠 | 글자와 버튼이 연속적으로 식별됨 |
| 외형 | Light·Dark·지원되는 Liquid Glass 외형 설정 | 강제 외형 없이 정상적으로 적응함 |
| 접근성 | 투명도 감소·대비 증가·동작 줄이기 | 사용자 정의 요소도 설정을 반영함 |
| 글자·언어 | 큰 접근성 글자·Bold Text·한국어·긴 번역 | 필수 내용과 행동이 잘리지 않음 |
| 조작 | 터치·스크롤·키보드·VoiceOver | 가려진 버튼이나 이름 없는 조작이 없음 |
| 데이터 상태 | 로딩·없음·실패·비활성·선택 | 상태와 가능한 다음 행동을 이해할 수 있음 |
| 기기·OS | 지원 iPhone 폭·iPad 창 크기·지원 최저 OS | 재배치와 fallback이 정상 동작함 |
| 성능 | 실제 기기의 스크롤·전환·반복 조작 | 효과 중복으로 인한 지연과 프레임 저하가 없음 |

형식 검증에는 공식 CLI를 사용할 수 있다. 재현 가능한 검증을 위해 이 문서 작성 시 확인한 패키지 버전을 명시한다. YAML 생략 선언은 누락을 숨기기 위한 것이 아니라 네이티브의 동적 값이 고정 CSS 토큰으로 잘못 변환되는 것을 막기 위한 것이다. [F1]

```sh
npx --yes --package=@google/design.md@0.4.0 designmd lint DESIGN.md
```

2026-10-08 작성 시 공식 CLI 0.4.0으로 검사한 결과는 오류 0개, 경고 0개, 정보 안내 4개였다. 정보 안내는 컴포넌트 수와 색·타이포그래피·곡률의 의도적 생략에 대한 것이다.

CLI 검증은 문서 구조와 정적 토큰만 다룬다. SwiftUI 빌드, 실제 합성된 유리 위의 대비, VoiceOver, 기기 성능을 검증해 주지 않는다. 제공된 SwiftUI 예제는 공식 API와 대조한 참조 코드이며, 이 문서 작성 환경에서 Xcode 빌드나 기기 실행을 수행한 결과는 아니다.

## Sources

형식은 Google Labs 공개 명세를 따르고, 플랫폼 동작은 Apple 공식 자료를 근거로 한다. 본문은 원문을 그대로 옮긴 것이 아니라 프로젝트에서 사용할 규칙으로 정리한 것이다. 숫자가 Apple의 조건부 가이드인지 이 문서의 프로젝트 기본값인지 해당 위치에 구분했다.

- [F1 — Google Labs DESIGN.md format specification, alpha](https://github.com/google-labs-code/design.md/blob/main/docs/spec.md)
- [F2 — Google Labs DESIGN.md repository and CLI](https://github.com/google-labs-code/design.md)
- [A1 — Apple: Liquid Glass 적용, 사용자 제공 한국어 문서](https://developer.apple.com/kr/documentation/technologyoverviews/adopting-liquid-glass)
- [A1-en — Apple: Adopting Liquid Glass, API 확인에 사용한 영문 문서](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [A2 — Apple HIG: Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [A3 — Apple: Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [A4 — Apple: glassEffect(_:in:)](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:))
- [A5 — Apple: GlassButtonStyle](https://developer.apple.com/documentation/swiftui/glassbuttonstyle)
- [A6 — Apple: GlassProminentButtonStyle](https://developer.apple.com/documentation/swiftui/glassprominentbuttonstyle)
- [A7 — Apple WWDC25: Get to know the new design system](https://developer.apple.com/videos/play/wwdc2025/356/)
- [A8 — Apple HIG: Color](https://developer.apple.com/design/human-interface-guidelines/color)
- [A9 — Apple HIG: Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- [A10 — Apple HIG: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [A11 — Apple: GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer)
- [A12 — Apple: Glass.clear](https://developer.apple.com/documentation/swiftui/glass/clear)
- [A13 — Apple: accessibilityReduceMotion](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion)
- [A14 — Apple: accessibilityReduceTransparency](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducetransparency)
