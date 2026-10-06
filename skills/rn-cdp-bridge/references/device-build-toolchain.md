# 실기기 debug 빌드를 막는 툴체인 함정

CDP로 붙기 전에 debug 빌드가 기기에 올라가야 한다. 아래는 그 단계에서 반복되는 실패다. 대부분 환경 핀이 없는 것이 원인이라 새 머신, 새 Xcode, 새 Android Studio에서 그대로 재발한다. 에러가 빌드 마지막 단계에서만 나는 경우가 많아 서명·코드 문제로 오진하기 쉽다.

## 공통: repo 경로를 옮긴 뒤의 좀비 절대경로

CMake와 CocoaPods 캐시는 절대경로를 박아 둔다. repo 디렉토리를 옮기면 옛 경로를 가리키는 캐시가 남는다.

- **Android `.cxx`**: `compile_commands.json`이 옛 경로를 가리킨다. AGP는 설정별 해시 디렉토리를 새로 만들 뿐 옛 것을 지우지 않는다. RN 네이티브 모듈(reanimated·worklets 등)의 stub PCH 생성 스크립트가 `.cxx`를 전수 순회하면서, 없는 파일의 `lastModified()`가 `0L`이라 `IllegalArgumentException: Negative time`으로 sync 전체가 죽는다. 판정은 `grep -rl "<옛 경로>" <.cxx 하위 디렉토리>`이고, 유효 캐시와 좀비가 공존하므로 `.cxx`를 통째로 지우지 말고 하위 디렉토리 단위로 지운다.
- **이 에러는 IDE sync에서만 난다.** stub PCH 생성이 `prepareKotlinBuildScriptModel`에 걸려 있어 `./gradlew assemble`로는 재현되지 않는다. 재현·검증은 `./gradlew prepareKotlinBuildScriptModel`.
- **iOS `Pods/Local Podspecs/hermes-engine.podspec.json`**: 다른 podspec json은 `pod install`마다 갱신되는데 이 파일만 옛 경로로 남아 `HERMES_CLI_PATH`가 잘못 주입된다. 컴파일·링크·번들이 다 성공한 뒤 맨 마지막 hermesc 단계에서만 실패한다. 그 json 하나를 지우고 `pod install`.

## Android

- **`INSTALL_FAILED_UPDATE_INCOMPATIBLE`**: 기기에 같은 applicationId가 다른 키(보통 release keystore)로 서명돼 깔려 있다. debug keystore로는 덮을 수 없으므로 `adb uninstall <pkg>` 후 설치한다. 기기의 앱 데이터가 지워진다는 점을 사용자에게 알린다.
- **Android Studio 업데이트 후 Gradle sync 실패**: Studio 번들 JBR 메이저가 올라가 Gradle이 지원하는 Java 범위를 벗어난다(`Incompatible Gradle JVM version`). `.idea/gradle.xml`의 `gradleJvm`이 `#GRADLE_LOCAL_JAVA_HOME` 매크로면 실제 경로는 `android/.gradle/config.properties`의 `java.home`에 있어 UI로는 원인이 안 보인다. Gradle JDK를 CLI와 같은 JDK(`#JAVA_HOME`, mise 등이 관리하는 것)로 맞추면 Studio 업데이트와 무관해진다.
- **`Activity class ... does not exist` / `am` result `-92`**: manifest 누락으로 단정하기 전에 증거를 대조한다. `dumpsys package`의 resolver table과 APK dex에는 Activity가 있는데 `cmd package resolve-activity`·`am start`가 못 찾으면, Gradle up-to-date 판단으로 stale·손상 APK가 설치된 것이다. `./gradlew :app:clean :app:assembleDebug` 후 `adb install -r --no-incremental <apk>`.

## iOS

- **기기가 provisioning profile에 없음**: `react-native run-ios`는 기기 등록 플래그를 넘기지 않는다. `xcodebuild ... -allowProvisioningUpdates -allowProvisioningDeviceRegistration`로 직접 빌드한다. 팀의 기기 슬롯을 하나 쓴다.
- **Ruby 3.4에서 `pod install`이 `bigdecimal` LoadError**: Ruby 3.4가 `bigdecimal`, `mutex_m`, `logger`, `drb`, `benchmark` 등을 default gem에서 뺐다. Gemfile에 추가한다. 프로젝트에 ruby 핀이 없으면 전역 버전 매니저가 올린 버전을 그대로 쓰게 된다.
- **Ruby 패치 버전이 바뀐 뒤 native gem 링크 깨짐**: `vendor/bundle`의 native gem이 이전 ruby의 `libruby`에 링크돼 있다. `bundle pristine`으로 재컴파일한다.
- **`pod`는 `bundle exec pod`로 부른다.** Gemfile이 cocoapods 버전 범위를 고정하는데 PATH의 `pod`는 그 범위 밖일 수 있다.
- **"Bundle React Native code and images" 단계가 옛 node로 돈다**: gitignore된 `ios/.xcode.env.local`에 박힌 node 경로가 우선한다. `toReversed is not a function` 같은 최신 JS API 에러가 이 단계에서만 나면 그 파일의 `NODE_BINARY`를 본다.
- **RN이 고정한 `fmt 11.0.2`가 최신 Apple clang(21)에서 자기 자신을 컴파일하지 못한다** (`call to consteval function ... is not a constant expression`). `-DFMT_USE_CONSTEVAL=0`은 효과가 없다 — `base.h`가 가드 없이 그 매크로를 재정의하고, podspec의 경고 억제 설정이 재정의 경고까지 숨긴다. Podfile `post_install`에서 `base.h`의 Apple clang 판별 분기를 패치한다. RN이 여러 podspec에서 버전을 고정하므로 fmt만 올릴 수 없다.
- **prebuilt xcframework가 Xcode 버전을 끌어올린다**: 벤더링된 바이너리 프레임워크의 `.swiftinterface`는 그것을 만든 컴파일러보다 오래된 Swift 컴파일러로 읽을 수 없다. device 슬라이스만 새 툴체인으로 빌드된 경우 시뮬레이터 빌드는 되고 실기기 빌드만 실패한다. `SWIFT_VERSION`은 언어 모드라 무관하다. 해당 Xcode 이상으로 올리거나 프레임워크를 다시 빌드한다.

## 실행 모델 차이

- **iOS 실기기 debug는 JS를 앱에 같이 번들한다**("Bundling for physical device"). Metro에 닿지 못하면 내장 번들로 standalone 실행되고, 그때는 fast refresh도 없고 `/json/list`에 타겟도 뜨지 않는다. CDP가 필요하면 기기가 Mac의 Metro에 닿는 네트워크(같은 LAN, 방화벽 허용)인지부터 본다.
- **Android debug는 Metro + `adb reverse tcp:8081 tcp:8081`이 필요하다.** USB를 다시 꽂으면 reverse가 사라진다.
