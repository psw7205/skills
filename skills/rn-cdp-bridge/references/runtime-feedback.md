# 런타임 피드백

## 2026-11-09 — Hermes 비동기 평가

- 환경: RN 0.83.0, Hermes, iOS 26.5 시뮬레이터. Metro `/json/list`에서 `nativePageReloads === true`인 앱 타깃에 연결.
- 기존 설명의 오류: async 문법 사용 불가와 `awaitPromise: true`가 완료값 반환을 보장한다는 단정.
- 요청: `Runtime.evaluate`, expression `(async function(){return 17})()`, `awaitPromise: true`, `returnByValue: true`.
- 응답: 문법 오류 없이 object 값 `{"_h":0,"_i":1,"_j":17,"_k":null}`. async 함수 표현식은 실행됐지만 CDP 결과는 숫자 17이 아니었음.
- 추가 확인: async 함수 안의 `await Promise.resolve()`도 실행됨. `globalThis.__asyncProbe`에 콜백 결과를 기록한 뒤 별도 평가로 `{done:true,value:17}`을 읽는 방식이 동작함.
- 정정: 문법 지원과 완료 대기를 분리하고, 고유 전역 키에 콜백 결과를 저장한 뒤 제한 시간 내 polling하도록 본문과 도메인 문서를 수정.
- 미검증: 최상위 await, 다른 RN·Hermes 버전, Android에서 같은 결과인지 여부.
