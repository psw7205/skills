# Humanizer pattern reference

AI 글쓰기 흔적을 찾고 줄이는 패턴 사전이다. 단일 표식으로 판정하지 말고, 여러 징후가 함께 나타나는지 본다.

## Core rule

- 의미와 정보 범위를 보존한다.
- 삭제보다 자연스러운 대체를 우선한다.
- 작성자의 기존 목소리가 있으면 그 패턴을 따른다.
- 출처 없는 구체 정보는 만들지 않는다.
- final rewrite에는 em dash `—`, en dash `–`, dash 역할의 `--`를 남기지 않는다.
- 한국어 입력은 `korean-patterns.md`를 함께 적용한다. 영어권 AI 티와 한국어 번역투는 겹치지만 같은 문제가 아니다.

## Content patterns

### 1. 과장된 significance, legacy, broader trend

징후:

- `stands as`, `serves as`, `testament`, `reminder`
- `vital`, `significant`, `crucial`, `pivotal`, `key`
- `underscores`, `highlights`, `reflects broader`, `symbolizing`
- `setting the stage`, `marking`, `shaping`, `turning point`
- 한국어: `중요한 전환점`, `상징한다`, `시사한다`, `역할을 한다`, `흐름을 보여준다`

수정:

- 의미 부여를 줄이고 실제 기능, 사건, 수치, 행위자를 쓴다.
- `X marked a pivotal moment`보다 `X happened in year to do Y`가 낫다.

### 2. notability와 media coverage 과잉

징후:

- 매체 이름을 나열하지만 어떤 주장과 연결되는지 불분명하다.
- `independent coverage`, `leading expert`, `active social media presence` 같은 말로 존재감을 증명하려 한다.

수정:

- 출처가 실제로 뒷받침하는 구체 주장만 남긴다.
- 단순 홍보성 나열은 지운다.

### 3. present participle padding

징후:

- `highlighting`, `underscoring`, `ensuring`, `reflecting`, `contributing to`, `showcasing`으로 문장 끝을 덧댄다.
- 한국어: `보여주며`, `시사하며`, `기여하며`, `강조하면서`가 문장마다 붙는다.

수정:

- 한 문장에 하나의 주장을 둔다.
- `A happened, highlighting B`를 `A happened. B is true because C`처럼 구체화한다.

### 4. 홍보 문체

징후:

- `boasts`, `vibrant`, `rich`, `profound`, `renowned`, `breathtaking`, `must-visit`, `stunning`
- 한국어: `풍부한`, `다채로운`, `획기적인`, `탁월한`, `압도적인`, `필수 방문지`

수정:

- 광고 형용사를 빼고 관찰 가능한 특징을 쓴다.

### 5. vague attribution과 weasel words

징후:

- `industry reports`, `observers have cited`, `experts argue`, `some critics argue`
- 한국어: `전문가들은`, `업계에서는`, `일각에서는`, `많은 이들이`

수정:

- 실제 출처, 사람, 문서, 날짜가 있으면 붙인다.
- 없으면 의견을 사실처럼 쓰지 않는다.

### 6. formulaic challenges and future outlook

징후:

- `Despite its... faces several challenges`
- `Despite these challenges... continues to thrive`
- `Future Outlook`, `Challenges and Legacy`

수정:

- 구체 문제와 조치만 남긴다.
- generic optimism을 삭제한다.

## Language patterns

### 7. AI vocabulary clustering

고빈도 단어:

- `additionally`, `align with`, `crucial`, `delve`, `emphasizing`, `enduring`, `enhance`
- `fostering`, `garner`, `highlight`, `interplay`, `intricate`, `key`, `landscape`
- `pivotal`, `showcase`, `tapestry`, `testament`, `underscore`, `valuable`, `vibrant`

한국어 대응:

- `더 나아가`, `핵심적인`, `중요한`, `복잡한 상호작용`, `생태계`, `환경`, `풍경`, `가치 있는`

수정:

- 반복되는 추상어를 구체 명사와 동사로 바꾼다.

### 8. copula avoidance

징후:

- `serves as`, `stands as`, `marks`, `represents`, `boasts`, `features`, `offers`

수정:

- 가능하면 `is`, `are`, `has`를 쓴다.
- 한국어도 `역할을 수행한다`보다 `이다`, `있다`, `갖고 있다`가 자연스러울 때가 많다.

### 9. negative parallelism과 tailing negation

징후:

- `not only... but also`
- `not just about X, it is about Y`
- 문장 끝에 `no guessing`, `no wasted motion`처럼 부정형 구호를 붙인다.

수정:

- 실제 주장만 한 문장으로 쓴다.
- tailing negation은 완전한 절로 풀어 쓴다.

### 10. rule of three

징후:

- 모든 항목이 셋으로 맞춰진다.
- `innovation, inspiration, and insight`처럼 소리 좋은 세 단어가 반복된다.

수정:

- 실제 필요한 개수만 남긴다.

### 11. elegant variation

징후:

- 같은 대상을 `protagonist`, `main character`, `central figure`, `hero`처럼 계속 바꿔 부른다.

수정:

- 같은 대상은 같은 이름으로 부른다. 독자가 길을 잃지 않게 한다.

### 12. false ranges

징후:

- `from X to Y`가 실제 범위가 아니라 멋을 위한 병렬이다.

수정:

- 목록이나 직접 설명으로 바꾼다.

### 13. passive voice와 subjectless fragments

징후:

- 행위자가 필요한데 빠져 있다.
- `No configuration file needed`, `The results are preserved automatically`

수정:

- 행위자나 시스템을 주어로 세운다.
- 다만 행위자가 중요하지 않은 기술 설명은 passive를 남겨도 된다.

## Style patterns

### 14. em dash, en dash, dash 역할의 double hyphen

수정 우선순위:

1. 문장 분리
2. comma
3. colon
4. parentheses
5. 문장 구조 변경

최종 확인:

- `—` 없음
- `–` 없음
- dash 역할의 `--` 없음

### 15. boldface 과잉

징후:

- 모든 핵심어를 `**bold**`로 강조한다.

수정:

- 강조를 대부분 제거한다. 필요한 경우 heading이나 문장 구조로 해결한다.

### 16. inline-header vertical list

징후:

- `- **Security:** ...`
- `- **Performance:** ...`

수정:

- 짧은 문단이나 평범한 bullet로 바꾼다.
- 항목이 꼭 필요하면 header를 줄이고 구체 내용부터 쓴다.

### 17. title case headings

징후:

- `## Strategic Negotiations And Global Partnerships`

수정:

- 영어 heading은 sentence case를 기본으로 한다.

### 18. emoji decoration

징후:

- heading, bullet, 단계에 emoji가 장식으로 붙는다.

수정:

- 의미가 없으면 제거한다.

### 19. curly quotes

징후:

- `"..."` 대신 `“...”`, `‘...’`

수정:

- 사용자 형식 요구가 없으면 straight quotes로 바꾼다.
- 단독으로는 AI 증거가 아니다.

## Communication patterns

### 20. chatbot framing

징후:

- `Of course!`, `Certainly!`, `I hope this helps`, `let me know`, `Would you like`
- 한국어: `물론입니다`, `좋은 질문입니다`, `도움이 되었으면 좋겠습니다`, `더 필요하시면 알려주세요`

수정:

- 본문 밖의 챗봇 응답 흔적을 제거한다.

### 21. knowledge-cutoff disclaimer와 speculative gap fill

징후:

- `as of`, `up to my last training update`, `based on available information`
- `maintains a low profile`, `keeps personal details private`, `likely grew up`
- 한국어: `제한적입니다`, `알려진 바가 많지 않습니다`, `사생활을 중시하는 것으로 보입니다`

수정:

- 확인된 사실만 쓴다.
- 모르면 `available sources do not document X`처럼 좁게 말하거나 삭제한다.

### 22. sycophantic tone

징후:

- `Great question`, `You're absolutely right`, `excellent point`

수정:

- 필요한 인정만 짧게 남긴다.

## Filler and rhetoric

### 23. filler phrases

치환:

- `in order to` -> `to`
- `due to the fact that` -> `because`
- `at this point in time` -> `now`
- `in the event that` -> `if`
- `has the ability to` -> `can`
- `it is important to note that` -> 보통 삭제

한국어:

- `~하기 위해서는`가 반복되면 `~하려면`
- `~라는 점에서`가 반복되면 직접 문장화
- `중요한 것은`이 반복되면 주장부터 시작

### 24. excessive hedging

징후:

- `could potentially possibly be argued`
- 한국어: `어느 정도`, `일부`, `가능성이 있을 수 있다`가 겹친다.

수정:

- 필요한 불확실성 하나만 남긴다.

### 25. generic positive conclusion

징후:

- `the future looks bright`
- `exciting times lie ahead`
- `major step in the right direction`

수정:

- 다음 행동, 실제 계획, 한계, 결론 중 하나로 끝낸다.

### 26. hyphenated word-pair overuse

징후:

- `third-party`, `cross-functional`, `client-facing`, `data-driven`, `decision-making`
- predicate position에서도 무조건 hyphen을 붙인다.

수정:

- attributive position에서는 hyphen을 유지할 수 있다.
- noun 뒤 predicate position에서는 보통 hyphen을 뺀다.

### 27. persuasive authority tropes

징후:

- `the real question is`, `at its core`, `in reality`, `what really matters`, `fundamentally`
- 한국어: `본질적으로`, `진짜 문제는`, `핵심은`, `결국 중요한 것은`

수정:

- ceremony를 빼고 바로 주장한다.

### 28. signposting announcements

징후:

- `let's dive in`, `let's explore`, `let's break this down`, `here's what you need to know`
- 한국어: `이제 살펴보겠습니다`, `하나씩 알아보겠습니다`, `먼저 짚고 넘어가겠습니다`

수정:

- 안내 문장을 지우고 본론으로 시작한다.

### 29. fragmented headers

징후:

- heading 다음에 heading을 한 줄로 반복하는 warm-up 문장이 온다.

수정:

- warm-up을 삭제하고 실제 내용부터 쓴다.

### 30. diff-anchored writing

징후:

- 일반 문서가 "무엇이 바뀌었는지"를 설명한다.
- `This was added to replace...`, `previously`, `now`

수정:

- 현재 상태를 직접 설명한다.
- changelog, release note, migration guide는 예외다.

### 31. manufactured punchlines와 staccato drama

징후:

- 짧은 문장 여러 개로 드라마를 만든다.
- `Then X arrived. No Y. No Z. The old rules were gone.`

수정:

- 한두 문장으로 합치고 실제 변화만 쓴다.

### 32. aphorism formulas

징후:

- `X is the Y of Z`
- `X becomes a trap`
- `X is not a tool but a mirror`
- `the language of`, `the currency of`, `the architecture of`

수정:

- 비유가 가리키는 구체 주장을 쓴다.

### 33. conversational rhetorical openers

징후:

- `Honestly?`, `Look,`, `Here's the thing`, `Let's be honest`, `Real talk`
- 한국어: `솔직히 말하면?`, `사실은요`, `쉽게 말해`, `문제는 이겁니다`

수정:

- theatrical pause를 지우고 바로 답한다.

## False positives

아래는 단독으로 AI 증거가 아니다.

- 완벽한 문법과 일관된 스타일
- formal vocabulary
- bland하거나 dry한 문장
- `however`, `moreover`, `additionally` 같은 전환어 한두 개
- em dash 하나
- curly quotes 하나
- common template formatting
- 사람이 원래 쓰는 letter-style greeting이나 sign-off
- 짧은 강조 문장 하나
- 출처 없는 문장 하나

## Human signals to preserve

- 구체적이고 이상하게 세부적인 정보
- 섞인 감정과 unresolved tension
- 특정 시기의 slang, meme, in-joke
- 작성자가 의식적으로 선택한 1인칭 판단
- 다양한 문장 길이
- 자연스러운 aside, parenthetical, self-correction
- 2022-11-30 이전에 작성된 글

## Final scan checklist

- 남은 `—`, `–`, dash 역할의 `--`가 없는가
- 의미가 보존됐는가
- 원문보다 더 많은 사실을 지어내지 않았는가
- 문장 길이가 지나치게 균일하지 않은가
- generic praise나 upbeat closer로 끝나지 않는가
- 작성 장르에 맞는 톤인가
- 한국어라면 호응, 조사, 높임, 어순이 자연스러운가
