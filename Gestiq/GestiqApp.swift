import SwiftUI

@main
struct GestiqApp: App {
    @State private var login = LoginModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if login.isCheckingSession {
                    sessionLoadingView
                } else if login.authenticatedSession != nil {
                    AuthenticatedRootView(model: login)
                } else {
                    LoginView(model: login)
                }
            }
            .task { await login.start() }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    await login.renewIfNeeded()
                    do { try await Task.sleep(for: .seconds(60)) }
                    catch { return }
                }
            }
        }
    }

    private var sessionLoadingView: some View {
        ZStack {
            LoginStyle.cream.ignoresSafeArea()
            VStack(spacing: 20) {
                Image("BrandLogo").resizable().scaledToFit().frame(width: 80, height: 80)
                    .clipShape(Circle())
                if let message = login.errorMessage {
                    Text(message).multilineTextAlignment(.center).foregroundStyle(LoginStyle.muted)
                    Button("Reintentar") { Task { await login.restoreSession() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(login.isLoading)
                } else {
                    ProgressView("Recuperando tu sesión…")
                }
            }
            .padding(24)
        }
        .tint(LoginStyle.teal)
        .preferredColorScheme(.light)
    }
}
