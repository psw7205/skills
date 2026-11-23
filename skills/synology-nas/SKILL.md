---
name: synology-nas
description: >
  Synology NAS(DSM File Station)의 파일을 번들 CLI `scripts/syno`로 찾고, 목록을 보고, 다운로드하는 스킬.
  로그인, 세션 캐시, 세션 만료 시 재로그인, 자체 서명 인증서 지문 고정을 CLI가 처리한다.
  "NAS에서 ~ 받아줘", "NAS에 ~ 있어?", "NAS 파일 찾아줘", "NAS 폴더 보여줘", "나스에서 다운로드",
  "시놀로지에서 파일 가져와", "download from NAS", "find file on NAS" 등에서 트리거.
---

# synology-nas

`SKILL_DIR`은 이 SKILL.md가 있는 디렉토리다. 셸 상태가 호출 간에 유지되지 않으므로 `"$SKILL_DIR/scripts/syno"` 절대 경로를 매번 쓴다. Web API를 curl로 직접 부르거나 로그인 흐름을 다시 만들지 않는다.

## 설정

접속 정보는 `~/.config/synology/nas.env`(권한 `600`)에서 읽는다. 파일이 없으면 사용자에게 만들어 달라고 요청하고, 계정 정보를 대화로 받지 않는다.

```
SYNO_URL=https://<nas-host>:5001
SYNO_USER=<계정>
SYNO_PASS=<비밀번호>
```

첫 HTTPS 접속 때 인증서 SHA-256 지문을 `~/.config/synology/cert.sha256`에 고정하고, 이후 접속마다 대조한다. 세션은 `~/.cache/synology/session.json`에 둔다. 2FA 계정은 지원하지 않는다.

## 명령

```bash
"$SKILL_DIR/scripts/syno" ls                            # 공유 폴더 목록
"$SKILL_DIR/scripts/syno" ls "/share/폴더"               # 폴더 내용: 종류, 크기, 수정시각, 경로
"$SKILL_DIR/scripts/syno" find 계약서                    # 모든 공유 폴더에서 이름 부분 일치 검색 (대소문자 무시)
"$SKILL_DIR/scripts/syno" find '*.pdf' "/share/폴더"     # 범위 지정, glob 가능
"$SKILL_DIR/scripts/syno" find 견적 -e pdf,xlsx          # 확장자 필터
"$SKILL_DIR/scripts/syno" get "/share/a/b.pdf" -o <dir>  # 파일 하나는 그대로 저장
"$SKILL_DIR/scripts/syno" get "/share/a/폴더" -o <dir>   # 폴더는 <이름>.zip, 여러 경로는 download.zip
"$SKILL_DIR/scripts/syno" call SYNO.FileStation.List getinfo path='["/share/x"]'  # 그 밖의 API, JSON 출력
```

## 작업 방식

- 경로를 모르면 `find`로 후보를 찾고, 하나로 좁혀지면 바로 받는다. 후보가 여럿이고 요청으로 고를 수 없을 때만 목록을 보여 주고 묻는다.
- 경로에 공백과 한글이 흔하므로 항상 따옴표로 감싼다.
- 저장 위치를 지정하지 않은 요청은 현재 작업 디렉토리에 받고, 받은 절대 경로를 보고한다.
- 수백 MB 이상 파일은 `find`/`ls`에 나온 크기를 받기 전에 알린다.
- 전체 공유 폴더 검색은 오래 걸릴 수 있다(최대 120초, 시간 초과 시 일부 결과). 폴더를 알면 범위를 준다.

## 에러

- `error 400`: 계정 정보 오류. 사용자가 `nas.env`를 확인해야 한다. 반복 시도는 DSM 자동 차단(`407`)을 부르므로 재시도하지 않는다.
- `error 408`: 경로 없음. `find`로 다시 찾는다.
- `인증서 지문 불일치`: NAS 인증서가 바뀌었거나 다른 서버다. 사용자 확인 없이 `cert.sha256`를 지우지 않는다.
- `error 119`가 재로그인 뒤에도 나면 CLI의 토큰 전달 방식 문제다. DSM은 POST 본문의 `SynoToken`을 무시하고 `X-SYNO-TOKEN` 헤더만 받는다.
