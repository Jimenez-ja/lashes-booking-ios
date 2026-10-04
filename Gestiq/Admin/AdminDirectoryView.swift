import SwiftUI

struct AdminDirectoryView: View {
    let kind: AdminDirectory
    let auth: LoginModel
    @State private var model = AdminDirectoryModel()
    @State private var search = ""
    @State private var page = 1
    private var requestKey: String { "\(page):\(search):\(auth.adminRevision)" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(kind == .clients ? "Cuentas, verificación y reservas" : "Responsables, servicios y actividad")
                        .font(LoginStyle.font(15)).foregroundStyle(LoginStyle.muted)
                    if model.isLoading {
                        ProgressView("Cargando \(kind.title.lowercased())…")
                            .frame(maxWidth: .infinity).padding(32)
                    } else if let error = model.error {
                        AdminRetryView(message: error) { Task { await load() } }
                    } else if model.people.isEmpty {
                        ContentUnavailableView("Sin resultados", systemImage: kind.icon,
                            description: Text(search.isEmpty ? "No hay registros para mostrar." : "Prueba con otro nombre, correo o teléfono."))
                    } else {
                        if let pagination = model.pagination {
                            Text("\(pagination.totalItems) \(kind.title.lowercased())")
                                .font(LoginStyle.font(14, bold: true)).foregroundStyle(LoginStyle.teal)
                        }
                        LazyVStack(spacing: 12) {
                            ForEach(model.people) { person in
                                NavigationLink {
                                    AdminDetailView(kind: kind, id: person.id, auth: auth)
                                } label: {
                                    row(person)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if let pagination = model.pagination, pagination.totalPages > 1 {
                        HStack {
                            Button { page -= 1 } label: {
                                Image(systemName: "chevron.left").frame(width: 44, height: 44)
                            }
                            .disabled(page <= 1 || model.isLoading).accessibilityLabel("Página anterior")
                            Spacer()
                            Text("\(pagination.page) de \(pagination.totalPages)")
                                .font(LoginStyle.font(14))
                            Spacer()
                            Button { page += 1 } label: {
                                Image(systemName: "chevron.right").frame(width: 44, height: 44)
                            }
                            .disabled(page >= pagination.totalPages || model.isLoading).accessibilityLabel("Página siguiente")
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .background(LoginStyle.cream.ignoresSafeArea())
            .navigationTitle(kind.title)
            .searchable(text: $search, prompt: kind == .clients ? "Nombre, correo o teléfono" : "Negocio, responsable o correo")
            .onChange(of: search) { _, newValue in
                if newValue.count > 100 { search = String(newValue.prefix(100)) }
                page = 1
            }
            .task(id: requestKey) {
                if !search.isEmpty {
                    do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                }
                await load()
            }
            .refreshable { await load() }
        }
        .tint(LoginStyle.teal)
        .preferredColorScheme(.light)
    }

    private func load() async { await model.load(kind: kind, page: page, search: search, auth: auth) }

    private func row(_ person: AdminPerson) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(kind == .clients ? person.name : person.companyName ?? "Negocio sin completar")
                        .font(LoginStyle.font(18, bold: true)).foregroundStyle(LoginStyle.ink)
                    if kind == .businesses {
                        Text(person.name).font(LoginStyle.font(14)).foregroundStyle(LoginStyle.muted)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(LoginStyle.teal).accessibilityHidden(true)
            }
            Text(person.email ?? "Sin correo registrado").font(LoginStyle.font(14))
                .foregroundStyle(LoginStyle.muted)
            HStack {
                Text(person.verification).foregroundStyle(person.emailVerifiedAt == nil ? LoginStyle.muted : LoginStyle.teal)
                Spacer()
                Text(person.status?.displayName ?? "Sin estatus").foregroundStyle(LoginStyle.ink)
            }
            .font(LoginStyle.font(12, relativeTo: .caption))
            HStack(spacing: 18) {
                Label("\(person.bookingCount.map(String.init) ?? "—") reservas", systemImage: "calendar")
                if kind == .businesses {
                    Label("\(person.serviceCount.map(String.init) ?? "—") servicios", systemImage: "list.bullet")
                }
            }
            .font(LoginStyle.font(13, relativeTo: .footnote)).foregroundStyle(LoginStyle.muted)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(LoginStyle.line, lineWidth: 1))
    }
}

struct AdminRetryView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Text(message).multilineTextAlignment(.center).foregroundStyle(LoginStyle.muted)
            Button("Reintentar", action: retry).buttonStyle(.borderedProminent)
        }
        .padding(24).frame(maxWidth: .infinity)
    }
}
