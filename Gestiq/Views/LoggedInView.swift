import SwiftUI

struct LoggedInView: View {
    @Bindable var model: LoginModel
    @State private var confirmsLogout = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Estás loggeado")
                        .font(LoginStyle.font(28, bold: true, relativeTo: .title))
                        .foregroundStyle(LoginStyle.ink)

                    if let user = model.authenticatedSession?.user {
                        VStack(alignment: .leading, spacing: 20) {
                            HStack(spacing: 16) {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundStyle(LoginStyle.teal)
                                    .accessibilityHidden(true)
                                Text(user.displayName)
                                    .font(LoginStyle.font(22, bold: true, relativeTo: .title2))
                                    .foregroundStyle(LoginStyle.ink)
                            }
                            Divider()
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Correo electrónico")
                                    .font(LoginStyle.font(13, relativeTo: .footnote))
                                    .foregroundStyle(LoginStyle.muted)
                                Text(user.email ?? "Sin correo registrado")
                                    .font(LoginStyle.font(16))
                                    .foregroundStyle(LoginStyle.ink)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(LoginStyle.line, lineWidth: 1))
                    }

                    if let message = model.errorMessage {
                        Text(message).foregroundStyle(.red)
                            .font(LoginStyle.font(14, relativeTo: .callout))
                            .accessibilityLabel("Error: \(message)")
                    }

                    Button { confirmsLogout = true } label: {
                        HStack(spacing: 10) {
                            if model.isLoading { ProgressView().tint(LoginStyle.teal) }
                            Label("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        .font(LoginStyle.font(16, bold: true))
                        .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isLoading)
                }
                .padding(24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .background(LoginStyle.cream.ignoresSafeArea())
            .navigationTitle("Mi cuenta")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("¿Quieres cerrar sesión?", isPresented: $confirmsLogout, titleVisibility: .visible) {
                Button("Cerrar sesión", role: .destructive) { Task { await model.logout() } }
                Button("Cancelar", role: .cancel) {}
            }
        }
        .tint(LoginStyle.teal)
        .preferredColorScheme(.light)
    }
}
