# pkm.nvim 개발 계획서 (Ralplan Consensus)

이 문서는 AI 에이전트(Planner, Architect, Critic) 간의 합의 도출(Consensus) 과정을 통해 작성된 `pkm.nvim` 플러그인의 최종 아키텍처 및 개발 계획입니다. 사용자의 실제 Neovim 생태계(dotfiles)를 깊이 반영하여 설계되었습니다.

## 1. 아키텍처 개요: 엄격한 씬 클라이언트 (Strict Thin Client) + 비동기 UX
`pkm.nvim`은 철저하게 **사용자 인터페이스(UI) 계층**의 역할만 수행합니다. 
모든 도메인 로직(프론트매터 생성, 타임스탬프, 경로 해석, 데이터 포맷팅 등)의 단일 진실 공급원(Single Source of Truth)은 파이썬으로 작성된 `pkm` CLI입니다. 
Neovim 내에서 Lua로 직접 파일을 조작(`io` 또는 `vim.api`)하여 CLI를 우회하는 일은 절대 없어야 합니다. 이를 통해 Neovim UI의 블로킹 없는(Non-blocking) 쾌적한 UX를 제공하는 데 집중합니다.

## 2. 핵심 구성 요소 및 생태계 통합 (Ecosystem Integration)
사용자의 기존 Neovim 환경에 완벽히 녹아들도록 다음 플러그인들과 깊이 통합합니다.

*   **Picker (`snacks.nvim`)**: 노트/태그 검색 및 선택의 핵심 인터페이스로 `Snacks.picker`를 사용합니다. (Telescope 배제)
*   **Notifications (`noice.nvim` & `fidget.nvim`)**: 비동기 작업 상태는 `fidget.progress` 또는 `vim.notify`의 진행률 추적 기능을 사용하여 스피너 형태로 우아하게 표시합니다. 원시 메시지 출력은 지양합니다.
*   **Rendering (`render-markdown.nvim`)**: 캡처 및 조회용으로 생성되는 모든 새 버퍼는 `filetype="markdown"`을 명시적으로 설정하여 `render-markdown.nvim`이 자동으로 렌더링되도록 합니다.
*   **Completion (`blink.cmp`)**: `[[wikilink]]` 및 `#tag` 자동 완성을 위한 `blink.cmp` 커스텀 소스를 제공합니다.
*   **Keymaps**: `<LocalLeader>p`를 접두사로 사용하는 표준화된 키맵을 제공합니다 (예: `<LocalLeader>pd`는 daily add).

## 3. 핵심 UX 개선 (낙관적 UI 및 능동적 복구)
가장 큰 위험 요소였던 비동기 처리 시의 "맹목적 전송(Blind Fire - 백그라운드 저장 실패 시 사용자가 인지하지 못하고 데이터가 유실되는 현상)" 문제를 다음과 같이 해결합니다.

*   **상태 추적 (Status Tracking)**: `fidget.progress` / `vim.notify`를 활용하여 비동기 작업 중 방해되지 않는 선에서 "저장 중..." 및 "저장 완료" 상태를 표시합니다.
*   **능동적 복구 (Active Recovery)**: 스크래치 버퍼를 닫은 후 백그라운드 CLI 저장이 실패할 경우, **플러그인이 자동으로 사용자의 작성 내용과 CLI 에러 메시지를 담아 스크래치 버퍼를 다시 엽니다.** 이를 통해 데이터 유실을 완벽히 방지합니다.
*   **낙관적 캐시 (Optimistic Cache)**: 캡처된 새 노트는 CLI 프로세스가 완전히 종료되기 전이라도 로컬 상태/피커에 즉시 주입되어, 대기 시간 없이 바로 링크를 걸거나 검색할 수 있게 합니다.

## 4. 구현 단계 (Phases)
*   **Phase 1: 기초 설정 및 헬스 체크**
    *   플러그인 디렉토리 구조 스캐폴딩 (`lua/pkm/`, `plugin/`, `doc/`)
    *   CLI 존재 여부를 확인하는 `health.lua` 구현.
    *   `<LocalLeader>p` 기반의 기본 키맵 구조 설계.
*   **Phase 2: 비동기 CLI 브릿지 및 오류 복구 시스템**
    *   `vim.system`을 활용한 `cli.lua` 비동기 실행 래퍼 구현.
    *   `fidget.nvim` / `noice.nvim` 연동을 통한 비동기 작업 상태(스피너) 표시.
    *   백그라운드 실패 시 에러를 캐치하는 복구 메커니즘 구축.
*   **Phase 3: 지연 없는 스크래치 버퍼 캡처 (Zero-Latency Capture)**
    *   `capture.lua` 구현: 팝업/스플릿 형태의 스크래치 버퍼 생성 (`filetype="markdown"` 강제 지정으로 `render-markdown.nvim` 연동).
    *   버퍼 저장/종료 시 CLI로 데이터를 비동기 전송(`pkm daily add`, `pkm note add`)하는 이벤트 바인딩.
*   **Phase 4: 피커(Picker) 및 자동완성(Completion) 통합**
    *   `Snacks.picker`를 활용한 `pkm search`, `pkm tags search`, `pkm note links` 검색 인터페이스 구현.
    *   `blink.cmp` 커스텀 소스 구현: 노트 작성 중 `[[` 입력 시 노트 제목 자동완성, `#` 입력 시 태그 자동완성 지원.

---

### ADR (Architecture Decision Record): 능동적 복구를 갖춘 비동기 씬 클라이언트
* **컨텍스트**: `pkm` CLI를 Neovim에 통합할 때 동기식 처리는 UI를 멈추게 하고, Lua로 로직을 재구현하는 '띡 클라이언트(Thick client)' 방식은 유지보수 부담과 로직 파편화를 초래합니다. 단순 비동기 처리는 백그라운드 에러 발생 시 사용자의 데이터가 유실되는 'Blind Fire' 위험이 있습니다. 또한, 사용자의 기존 Neovim 생태계(`snacks.nvim`, `blink.cmp`, `fidget.nvim` 등)를 적극 활용해야 합니다.
* **결정**: 엄격한 비동기 씬 클라이언트(Strict Asynchronous Thin Client) 아키텍처를 채택합니다. 모든 도메인 로직은 `pkm` CLI에 위임하되, 백그라운드 저장 실패 시 사용자의 작성 버퍼를 강제로 다시 열어주는 '능동적 복구(Active Recovery)' 메커니즘과 '낙관적 캐싱(Optimistic caching)'을 통해 체감 지연 시간을 0으로 만듭니다. UI 컴포넌트는 사용자의 기존 플러그인 생태계에 강하게 결합(Tight coupling)하여 일관된 경험을 제공합니다.
* **결과**: UI 반응성은 완벽히 유지되며, 파이썬 CLI가 유일한 도메인 로직 관리자로 남습니다. 능동적 복구로 데이터 유실이 방지되며, 기존 dotfiles 생태계와의 완벽한 조화를 이룹니다.