# 이메일 회원가입·로그인 설계

- 작성일: 2026-10-11
- 브랜치: `email-login`
- 관련 문서: 메인 설계 `2026-09-06-overseas-travel-app-design.md` §"로그인 수단 확장 지점"

## 1. 배경

로그인은 Google 하나뿐이고, 실패해도 화면에 안내가 없으며, 앱 안에 로그아웃할 곳이 없다. 메인 설계는 처음부터 이메일/비밀번호 가입을 "Firebase Email/Password provider + 화면 3개, 서버 변경 없음"으로 추가할 수 있게 해 두었다(`AuthRepository` 추상화, `displayName`·`email` nullable). 자체 회원 테이블·JWT는 만들지 않는다(CLAUDE.md).

## 2. 결정 사항 (2026-10-11)

| 질문 | 결정 |
|---|---|
| 방식 | Firebase Email/Password. 서버 코드·의존성 변경 없음 |
| 가입 입력 | 닉네임(1~20자) + 이메일 + 비밀번호(6자 이상) + 비밀번호 확인. 닉네임은 Firebase `displayName` |
| 로그아웃 위치 | 여행 탭 헤더의 계정 아이콘 → 계정 시트(닉네임·이메일·[로그아웃]) |
| Google/이메일 같은 주소 충돌 | 계정 연결 없이 안내 문구만 |

범위 밖: 계정 연결(`linkWithCredential`), 이메일 인증 메일, 닉네임 변경, Firestore `users/{uid}` 문서(Plan D).

사용자 작업: Firebase 콘솔 → Authentication → Sign-in method → 이메일/비밀번호 사용 설정.

## 3. 화면

### 3.1 로그인 (`/login`)
이메일·비밀번호 입력, [로그인], [비밀번호를 잊으셨나요?] → `/login/reset`, "또는" 구분선, [Google로 계속하기], 하단 "계정이 없으신가요? [회원가입]" → `/login/signup`. 실패 시 폼 아래 한국어 안내. Google 로그인을 사용자가 취소하면 안내하지 않는다.

### 3.2 회원가입 (`/login/signup`)
닉네임·이메일·비밀번호·비밀번호 확인. [가입하기]를 누르면 먼저 입력 검사를 하고, 통과하지 못하면 요청을 보내지 않고 각 칸 아래에 안내한다. 성공하면 자동 로그인되어 여행 탭으로 간다(라우터 redirect).

### 3.3 비밀번호 재설정 (`/login/reset`)
이메일 입력 → [재설정 메일 보내기] → "재설정 메일을 보냈습니다. 메일함을 확인해 주세요." 가입되지 않은 이메일이어도(서버가 그렇게 알려 와도) 같은 문구 — 가입 여부를 노출하지 않는다.

### 3.4 계정 시트
여행 탭 헤더 오른쪽 계정 아이콘 → 바텀시트: 표시 이름(`AppUser.displayLabel`), 이메일(있을 때), [로그아웃]. 로그아웃하면 라우터가 로그인 화면으로 보낸다. 여행 목록 캐시·선택 여행은 이미 uid별로 나뉘어 있다.

### 3.5 입력 검사 문구

| 칸 | 조건 | 문구 |
|---|---|---|
| 닉네임 | 공백 제외 비었음 / 20자 초과 | 닉네임을 입력해 주세요. / 닉네임은 20자 이하로 입력해 주세요. |
| 이메일 | 비었음 / 형식 오류 | 이메일을 입력해 주세요. / 이메일 형식을 확인해 주세요. |
| 비밀번호 | 비었음 / 6자 미만(가입만) | 비밀번호를 입력해 주세요. / 비밀번호는 6자 이상이어야 합니다. |
| 비밀번호 확인 | 불일치 | 비밀번호가 일치하지 않습니다. |

### 3.6 오류 문구 (`AuthErrorCode` → 문구)

| 코드 | Firebase 코드 | 문구 |
|---|---|---|
| invalidCredential | invalid-credential, wrong-password, user-not-found, INVALID_LOGIN_CREDENTIALS | 이메일 또는 비밀번호가 맞지 않습니다. |
| emailAlreadyInUse | email-already-in-use | 이미 가입된 이메일입니다. 이메일 또는 Google로 로그인해 주세요. |
| accountExistsWithDifferentCredential | account-exists-with-different-credential | 이메일로 가입된 계정입니다. 이메일로 로그인해 주세요. |
| weakPassword | weak-password | 비밀번호는 6자 이상이어야 합니다. |
| invalidEmail | invalid-email | 이메일 형식을 확인해 주세요. |
| network | network-request-failed | 네트워크를 확인해 주세요. |
| tooManyRequests | too-many-requests | 잠시 후 다시 시도해 주세요. |
| unknown | 그 외 전부 | 로그인하지 못했습니다. 잠시 후 다시 시도해 주세요. |

Firebase는 이메일 열거 보호 때문에 이미 가입된 주소가 Google 계정인지 이메일 계정인지 알려주지 않으므로 `emailAlreadyInUse` 문구는 두 경우를 함께 안내한다. Gmail 주소는 Firebase가 Google을 신뢰 제공자로 보므로, 이메일로 가입한 Gmail 계정에 Google로 로그인하면 오류 없이 같은 계정이 되고 이메일 비밀번호는 사라진다(Firebase 기본 동작, 받아들임).

## 4. 구조

- `AuthRepository`에 추가: `AppUser? get currentUser`, `signInWithEmail({email, password})`, `signUpWithEmail({email, password, nickname})`, `sendPasswordReset(email)`. 가입은 계정 생성 → `updateDisplayName(nickname)` → `reload`.
- `currentUser`가 필요한 이유: `authStateChanges()`는 계정 생성 순간(닉네임 저장 전)에 방출하므로 그 `AppUser`에는 닉네임이 없다. `userChanges()`로 바꾸면 프로필·토큰 갱신마다 방출되어 `_Root`가 라우터를 새로 만들고 화면 스택이 초기화되므로 쓰지 않는다. 계정 시트는 열 때 `currentUser`를 읽는다.
- 실패는 `AuthException(AuthErrorCode)`로 통일. `mapFirebaseAuthCode(String)`와 `authErrorMessage(AuthErrorCode)`는 순수 함수. 취소는 기존 `AuthCancelledException`.
- `FirebaseAuthRepository`는 모든 Firebase 호출을 `FirebaseAuthException` → `AuthException`으로 바꿔 던진다. `DevAuthRepository`, 테스트 `FakeAuthRepository`도 새 메서드를 구현한다.
- 라우터: 로그아웃 상태에서는 `/login`으로 시작하는 경로(`/login`, `/login/signup`, `/login/reset`)만 허용, 로그인 상태에서 이 경로면 `/visa`로. `createRouter`의 `onSignIn` 콜백은 없애고 로그인 화면이 `authRepositoryProvider`를 직접 쓴다.

## 5. 테스트

- 단위: `mapFirebaseAuthCode`, `authErrorMessage`, 입력 검사 함수.
- 위젯(`FakeAuthRepository`): 로그인(성공 호출·실패 문구·Google 취소 무안내·화면 이동), 회원가입(검사·호출 인자·중복 이메일 문구), 재설정(발송 문구, 미가입도 같은 문구), 계정 시트(표시·로그아웃).
- 라우터: 로그아웃 상태에서 회원가입 화면 진입.
