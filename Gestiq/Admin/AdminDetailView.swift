import SwiftUI

struct AdminDetailView: View {
    let kind: AdminDirectory
    let id: String
    let auth: LoginModel
    @State private var model = AdminDetailModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let notice = model.notice {
                    Text(notice).foregroundStyle(LoginStyle.teal).font(LoginStyle.font(15, bold: true))
                }
                if let error = model.mutationError {
                    Text(error).foregroundStyle(.red).font(LoginStyle.font(14))
                }
                if model.isLoading {
                    ProgressView("Cargando detalle…").frame(maxWidth: .infinity).padding(40)
                } else if let error = model.error {
                    AdminRetryView(message: error) { Task { await load() } }
                } else if let person = model.person {
                    details(person)
                }
            }
            .padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }
        .background(LoginStyle.cream.ignoresSafeArea())
        .navigationTitle(kind == .clients ? "Detalle del cliente" : "Detalle del negocio")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }

    }

    private func load() async { await model.load(kind: kind, id: id, auth: auth) }

    @ViewBuilder
    private func details(_ person: AdminPerson) -> some View {
        Text(kind == .clients ? person.name : person.company?.name ?? "Negocio sin completar")
            .font(LoginStyle.font(26, bold: true, relativeTo: .title)).foregroundStyle(LoginStyle.ink)
        section("Datos de la cuenta") {
            field("Nombre", person.name)
            field("Correo", person.email)
            field("Verificación", person.verification)
            field("Teléfono", person.phone)
            field("Estatus", person.status?.displayName)
            field("Registro", adminDate(person.registered))
        }
        AdminAccountActionView(person: person, kind: kind, auth: auth, model: model)
        section("Actividad") {
            if let summary = person.bookingSummary {
                field("Reservas", String(summary.total))
                field("Completadas", String(summary.completed))
                field("Canceladas", String(summary.canceled))
                field("No asistió", String(summary.noShow))
                field("Última cita", adminDate(summary.lastBookingDate))
            } else if let summary = person.businessSummary {
                field("Reservas", String(summary.totalBookings))
                field("Servicios", String(summary.services))
                field("Completadas", String(summary.completed))
                field("Canceladas", String(summary.canceled))
                field("No asistió", String(summary.noShow))
            } else {
                Text("Actividad no disponible").foregroundStyle(LoginStyle.muted)
            }
        }
        if kind == .businesses {
            if let company = person.company {
                section("Datos del negocio") {
                    field("Descripción", company.description)
                    let address = [company.neighborhood, company.city, company.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
                    field("Ubicación", address.isEmpty ? nil : address)
                    field("Local de prueba", yesNo(company.isTest))
                    field("Cancelación en línea", yesNo(company.allowClientCancellation))
                    field("Reagenda en línea", yesNo(company.allowClientReschedule))
                    field("Anticipación mínima", company.cancellationNoticeHours.map { "\($0) horas" })
                }
                section("Horarios de atención") {
                    if let hours = company.companyHours, !hours.isEmpty {
                        ForEach(hours.sorted { $0.day < $1.day }, id: \.day) { hour in
                            field(dayName(hour.day), "\(hour.open.prefix(5)) – \(hour.close.prefix(5))")
                        }
                    } else { Text("Sin horarios configurados").foregroundStyle(LoginStyle.muted) }
                }
            } else {
                section("Negocio") { Text("El responsable todavía no tiene un negocio registrado.") }
            }
            section("Mercado Pago") {
                if let payments = person.paymentConfiguration {
                    field("Cuenta vinculada", payments.linked ? "Vinculada" : "Sin vincular")
                    if payments.linked {
                        field("Modo registrado", payments.liveMode.map { $0 ? "Producción" : "Pruebas" })
                        field("Fecha de vinculación", adminDate(payments.linkedAt))
                    }
                    Text("Configuración guardada; no comprueba la disponibilidad para cobrar.")
                        .font(LoginStyle.font(13, relativeTo: .footnote)).foregroundStyle(LoginStyle.muted)
                } else { Text("Configuración no disponible").foregroundStyle(LoginStyle.muted) }
            }
        }
        section("Citas recientes") {
            if let bookings = person.recentBookings {
                if bookings.isEmpty { Text("Sin reservas registradas").foregroundStyle(LoginStyle.muted) }
                ForEach(bookings) { booking in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(booking.serviceName ?? "Servicio").font(LoginStyle.font(16, bold: true))
                        Text(kind == .clients ? booking.companyName ?? "Negocio" : booking.clientName ?? "Cliente sin cuenta")
                        Text(adminDate(booking.date)).foregroundStyle(LoginStyle.muted)
                        Text(booking.outcome).foregroundStyle(LoginStyle.teal)
                    }
                    .font(LoginStyle.font(14))
                    .padding(.vertical, 6)
                    if booking.id != bookings.last?.id { Divider() }
                }
            } else { Text("Citas no disponibles").foregroundStyle(LoginStyle.muted) }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(LoginStyle.font(18, bold: true, relativeTo: .headline))
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .foregroundStyle(LoginStyle.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20).background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(LoginStyle.line, lineWidth: 1))
    }

    private func field(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(LoginStyle.font(12, relativeTo: .caption)).foregroundStyle(LoginStyle.muted)
            Text(value.flatMap { $0.isEmpty ? nil : $0 } ?? "No disponible")
                .font(LoginStyle.font(15)).textSelection(.enabled)
        }
    }

    private func yesNo(_ value: Bool?) -> String? { value.map { $0 ? "Sí" : "No" } }
    private func dayName(_ day: Int) -> String {
        let days = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"]
        return days.indices.contains(day) ? days[day] : "Día \(day)"
    }
}

struct AuthenticatedRootView: View {
    let model: LoginModel
    var body: some View {
        TabView {
            if model.authenticatedSession?.user.isAdministrator == true,
               model.authenticatedSession?.user.allows(route: "/dashboard") == true {
                AdminDashboardView(auth: model)
                    .tabItem { Label("Inicio", systemImage: "chart.bar") }
            }
            if model.authenticatedSession?.user.canManageBusiness == true {
                CompanyEditorView(auth: model).tabItem { Label("Mi negocio", systemImage: "building.2") }
                BusinessServicesView(auth: model).tabItem { Label("Servicios", systemImage: "list.bullet.rectangle") }
            }
            ForEach(AdminDirectory.allCases.filter { model.authenticatedSession?.user.allows(route: $0.route) == true }) { kind in
                AdminDirectoryView(kind: kind, auth: model)
                    .tabItem { Label(kind.title, systemImage: kind.icon) }
            }
            LoggedInView(model: model)
                .tabItem { Label("Mi cuenta", systemImage: "person.crop.circle") }
        }
        .tint(LoginStyle.teal)
        .preferredColorScheme(.light)
    }
}

struct AdminAccountActionView: View {
    let person: AdminPerson
    let kind: AdminDirectory
    let auth: LoginModel
    let model: AdminDetailModel
    @State private var pendingAction: AccountAction?

    var body: some View {
        Group {
            if let action = AccountAction.availableAction(for: person, user: auth.authenticatedSession?.user) {
                Button {
                    pendingAction = action
                } label: {
                    HStack {
                        if model.isMutating { ProgressView() }
                        Label(action.title, systemImage: action == .deactivate ? "person.crop.circle.badge.minus" : "person.crop.circle.badge.checkmark")
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(action == .deactivate ? .red : LoginStyle.teal)
                .disabled(model.isMutating || model.isLoading)
            }
        }
        .confirmationDialog(pendingAction?.title ?? "Cambiar estado", isPresented: Binding(
            get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }
        ), titleVisibility: .visible) {
            if let action = pendingAction {
                Button(action.title, role: action == .deactivate ? .destructive : nil) {
                    Task { await model.changeStatus(action, kind: kind, id: person.id, auth: auth) }
                }
            }
            Button("Cancelar", role: .cancel) { pendingAction = nil }
        } message: {
            Text(pendingAction == .deactivate
                ? "La cuenta de \(person.name) no podrá iniciar sesión."
                : "La cuenta de \(person.name) volverá a estar activa.")
        }
    }
}
