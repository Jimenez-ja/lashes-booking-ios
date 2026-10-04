# iOS map

Native SwiftUI iPhone app; iOS 17+, scheme `Gestiq` in `Gestiq.xcodeproj`. No third-party dependencies.

- `Gestiq/GestiqApp.swift`: owns observable session state; restores on launch, selects retry/login/account screens and checks access expiry every minute while active.
- `Gestiq/Views/LoginView.swift`: email/password form, loading and server errors. Matches web Login.scss brand colors/card layout; Arial uses the web fallback font with Dynamic Type. Login is the initial screen; no external navigation links. Registration, recovery and verification are outside the current app scope.
- `Gestiq/Assets.xcassets/BrandLogo.imageset`: logo copied from the web frontend's `src/assets/images/logo.png`; compiled through the target Resources phase.
- `Gestiq/Views/LoggedInView.swift`: native account screen with authenticated name/email, brand styling and confirmed logout.
- `Gestiq/Auth/LoginModel.swift`: main-actor state, serialized auth operations, restore/retry, login/logout and renewal. Temporary failures retain persistence; rejected refresh returns to login.
- `Gestiq/Auth/AuthClient.swift`: ephemeral URLSession without automatic cookie storage; `POST /api/auth/login` with `{ identifier, password }`, `/auth/refreshToken` and `/auth/logout`. Sends required Origin/session headers and saved refresh cookie. Response `{ data: { token, user } }`; saves rotated `gestiq_refresh` cookie from Set-Cookie. Access token/profile remain in memory.
- `Gestiq/Auth/KeychainSessionStore.swift`: refresh cookie and expiry in device-only Keychain, scoped to API URL. No credentials in UserDefaults or plain files.
- `Config/App.xcconfig`: public API URL and allowed web origin injected into `Gestiq/Info.plist`. Never put credentials here.
- `Tests/AuthClientChecks.swift`: mocked network/store checks for auth contract, restore, temporary failures/retry, logout and revocation; command in README. Does not access production or test real Keychain storage.

Build: `xcodebuild -project Gestiq.xcodeproj -scheme Gestiq -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build`. Requires full Xcode; Command Line Tools alone cannot compile SwiftUI for iOS.
