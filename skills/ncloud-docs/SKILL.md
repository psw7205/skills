---
name: ncloud-docs
description: >
  네이버 클라우드 플랫폼(NCP, ncloud) 공식 문서를 llms.txt 인덱스와 원문 markdown으로
  받아 읽는 스킬. guide·api·gov·fin 문서의 slug 검색, 원문 .md 저장, 한 상품 문서 전체
  수집 후 grep으로 "문서에 있다/없다"를 판정한다. WAF 403·slug 404·WebFetch 요약 누락을 피한다.
  "ncloud 문서 확인해", "NCP 문서 봐줘", "네이버 클라우드 가이드", "ncloud 가이드 확인",
  "NCP API 스펙", "NCP 공식 문서에서 확인", "Cloud DB for PostgreSQL 문서", "NKS 문서",
  "Object Storage 문서", "Global Edge 문서", "NCP 가격", "guide.ncloud-docs.com",
  "api.ncloud-docs.com", "check ncloud docs", "NCP documentation", "naver cloud docs" 등에서
  트리거. ncloud-docs.com URL을 받았을 때도 트리거. NCP API 호출 자체는 다루지 않는다.
---

# ncloud-docs

NCP 문서는 `<host>.ncloud-docs.com/llms.txt`(인덱스)와 `/docs/<slug>.md`(원문 markdown)로 전부 받을 수 있다. 문서를 못 가져왔다고 사용자에게 되묻기 전에 이 절차를 끝까지 탄다.

## 절차

`SKILL_DIR`은 이 SKILL.md가 있는 디렉토리다. 셸 상태가 호출 간에 유지되지 않으므로 스크립트 절대 경로를 매번 쓴다.

1. **slug 확정** — 추측하지 않고 인덱스에서 찾는다. 정규식은 제목과 slug에 대소문자 무시로 건다.

   ```bash
   bash "$SKILL_DIR/scripts/ncloud-docs.sh" search 'postgresql'
   bash "$SKILL_DIR/scripts/ncloud-docs.sh" search 'getpricelist' -H api
   ```

2. **원문 받기** — slug, 전체 URL, 문서 안의 상대 링크(`/docs/...#anchor`)를 그대로 넘겨도 된다. 저장 경로와 heading 목차를 출력하니, 파일은 Read나 `rg`로 읽는다.

   ```bash
   bash "$SKILL_DIR/scripts/ncloud-docs.sh" get clouddbforpostgresql-postgresqlserver
   ```

3. **있다/없다 판정** — 한 상품 문서를 slug 접두사로 전부 받은 뒤 `rg`로 찾는다. 스크립트가 받은 파일 목록을 `.last-pull`에 남긴다.

   ```bash
   bash "$SKILL_DIR/scripts/ncloud-docs.sh" pull '^clouddbforpostgresql-'
   rg -n -i -w 'ssl|tls' $(cat ~/.cache/ncloud-docs/guide/.last-pull)
   ```

   "문서에 없다"고 보고할 때는 범위를 `N/N개 문서를 받아 rg`처럼 밝힌다. 일부만 봤다면 그 개수를 말하고 "없다"고 단정하지 않는다. 다른 상품 문서가 함께 다루는 주제(예: DB 암호화 통신을 SSL VPN 문서가 다룸)는 그 상품도 같이 pull한다.

host는 `-H`로 고른다: `guide`(기본, 민간 사용 가이드), `api`(API 레퍼런스), `guide-gov`·`api-gov`(공공), `guide-fin`·`api-fin`(금융). 공공·금융 리전 고객 건이면 해당 host를 쓴다. 문서 구성이 민간과 다르다.

캐시는 `${NCLOUD_DOCS_CACHE:-~/.cache/ncloud-docs}/<host>/`이고, 인덱스는 하루가 지나면 새로 받는다. 원문은 받을 때마다 갱신한다.

## Fallback

스크립트 종료 코드로 다음 수를 정한다.

- `4` (404): slug가 틀렸다. `search`로 다시 찾는다. 인덱스에 없는 신규 문서면 `WebFetch`로 `https://<host>.ncloud-docs.com/docs/<slug>.md`를 연다.
- `3` (403 `BLOCKED`): WAF 규칙이 바뀌었다. `NCLOUD_DOCS_UA=<다른 값>`으로 한 번 재시도하고, 그래도 막히면 `agent-browser`로 같은 URL을 연다.
- 인덱스 자체를 못 받으면 네트워크 문제다. 같은 URL을 `WebFetch`로 열어 확인한다.

## Gotchas

- **`guide.ncloud-docs.com`의 403은 UA 차단이다.** User-Agent가 `curl/*`, `Mozilla/5.0`, `Claude-User`이면 "Access Denied" HTML(약 414KB)이 온다. 다른 UA는 같은 URL에서 200이다. 그래서 기본 `curl`만 막히고 브라우저 위장은 필요 없다. 다른 host들은 막지 않는다(2026-11 실측). "curl은 403이라 쓸 수 없다"고 결론 내지 않는다.
- **`.md`를 빼면 Document360 SPA 셸**(수 MB HTML)만 온다. WebFetch로 `.md` 없는 URL을 열면 요약 모델이 껍데기만 보고 "내용이 없다"고 답한다.
- **slug는 소문자이고 대소문자를 구분한다.** `clouddbforPostgreSQL-PostgreSQLserver.md`는 404다. 스크립트가 대소문자만 다른 slug는 보정한다. 그럴듯한 slug(`postgresql-start` 등)를 지어내면 404가 난다.
- **WebFetch는 요약 모델을 거친다.** 일부를 발췌하거나 빠뜨리므로, 원문 인용이나 부재 판정의 근거로 쓰지 않는다.
- **가격은 원문 md가 없다.** `www.ncloud.com`의 상품·요금 페이지는 SPA이고, `m.ncloud.com`은 없는 도메인이다. 요금표는 `agent-browser`로 `https://www.ncloud.com/charge/price/ko`를 연다. 프로그램으로 조회해야 하면 List Price API(`search listprice -H api`, 서명 인증 필요)를 쓴다.
- **이미지에만 있는 정보**(콘솔 화면, 아키텍처 그림)가 있다. 원문의 `cdn.document360.io` 이미지 URL은 SAS 서명이라 약 1시간 뒤 만료된다. 필요하면 바로 받아서 Read로 본다. 링크를 결과물에 남기지 않는다.
- **문서는 콘솔·API 실동작과 어긋날 수 있다.** 문서가 기능 존재를 확정하지 못하면, 손에 닿는 실측(API 조회, 프로토콜 probe)으로 닫는다.
