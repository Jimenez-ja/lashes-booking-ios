import SwiftUI

// Matches the web login tokens in _variables.scss and Login.scss.
enum LoginStyle {
    static let cream = Color(red: 248 / 255, green: 246 / 255, blue: 241 / 255)
    static let ink = Color(red: 23 / 255, green: 53 / 255, blue: 74 / 255)
    static let muted = Color(red: 80 / 255, green: 101 / 255, blue: 116 / 255)
    static let teal = Color(red: 8 / 255, green: 126 / 255, blue: 131 / 255)
    static let line = Color(red: 215 / 255, green: 226 / 255, blue: 223 / 255)
    static let inputBorder = Color(red: 187 / 255, green: 217 / 255, blue: 212 / 255)
    static let icon = Color(red: 12 / 255, green: 133 / 255, blue: 137 / 255)

    // Arial is also the web's fallback when Roboto is unavailable.
    static func font(_ size: CGFloat, bold: Bool = false, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(bold ? "Arial-BoldMT" : "ArialMT", size: size, relativeTo: style)
    }
}

struct LoginView: View {
    @Bindable var model: LoginModel
    @FocusState private var focusedField: Field?
    @State private var showsPassword = false
    private enum Field { case email, password }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    card
                        .frame(maxWidth: 420)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(LoginStyle.cream.ignoresSafeArea())
        .tint(LoginStyle.teal)
        .preferredColorScheme(.light)
    }

    private var card: some View {
        VStack(spacing: 0) {
            Image("BrandLogo")
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 96)
                .clipShape(Circle())
                .overlay(Circle().stroke(LoginStyle.inputBorder, lineWidth: 2))
                .accessibilityLabel("Gestiq")
                .padding(.bottom, 16)

            Text("BIENVENIDO A GESTIQ")
                .font(LoginStyle.font(10, bold: true, relativeTo: .caption2))
                .tracking(2)
                .foregroundStyle(LoginStyle.teal)
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)

            Text("Inicio de sesión")
                .font(LoginStyle.font(30, bold: true, relativeTo: .title))
                .tracking(-1)
                .foregroundStyle(LoginStyle.ink)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 12)

            Text("Ingresa con tu correo electrónico")
                .font(LoginStyle.font(14, relativeTo: .subheadline))
                .foregroundStyle(LoginStyle.muted)
                .multilineTextAlignment(.center)
                .padding(.bottom, 24)

            VStack(spacing: 20) {
                inputContainer(icon: "envelope", focused: focusedField == .email) {
                    TextField("Correo electrónico", text: $model.email)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                        .accessibilityLabel("Correo electrónico")
                }
                inputContainer(icon: "lock", focused: focusedField == .password) {
                    Group {
                        if showsPassword {
                            TextField("Contraseña", text: $model.password)
                        } else {
                            SecureField("Contraseña", text: $model.password)
                        }
                    }
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { submit() }
                    .accessibilityLabel("Contraseña")
                    Button {
                        showsPassword.toggle()
                    } label: {
                        Image(systemName: showsPassword ? "eye.slash" : "eye")
                            .foregroundStyle(LoginStyle.muted)
                            .frame(minWidth: 32, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showsPassword ? "Ocultar contraseña" : "Mostrar contraseña")
                }
            }
            .disabled(model.isLoading)
            .padding(.bottom, 24)

            if let message = model.errorMessage {
                Text(message)
                    .font(LoginStyle.font(14, relativeTo: .callout))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Error: \(message)")
                    .padding(.bottom, 16)
            }

            Button(action: submit) {
                HStack(spacing: 10) {
                    if model.isLoading { ProgressView().tint(.white) }
                    Text(model.isLoading ? "Iniciando sesión…" : "Entrar")
                        .font(LoginStyle.font(18, relativeTo: .headline))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white)
                .background(LoginStyle.teal.opacity(model.canSubmit ? 1 : 0.55))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(!model.canSubmit)

        }
        .padding(.horizontal, 20)
        .padding(.vertical, 28)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(LoginStyle.line, lineWidth: 1))
        .shadow(color: LoginStyle.ink.opacity(0.08), radius: 23, x: 0, y: 18)
    }

    private func inputContainer<Content: View>(icon: String, focused: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(LoginStyle.icon)
                .accessibilityHidden(true)
            content()
        }
        .font(LoginStyle.font(16))
        .foregroundStyle(LoginStyle.ink)
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(focused ? LoginStyle.icon : LoginStyle.inputBorder, lineWidth: focused ? 2 : 1))
    }

    private func submit() {
        guard model.canSubmit else { return }
        focusedField = nil
        Task { await model.login() }
    }
}
