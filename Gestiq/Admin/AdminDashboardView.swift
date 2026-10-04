import SwiftUI

struct AdminDashboardView: View {
    let auth: LoginModel
    @State private var model = AdminDashboardModel()
    @State private var selectedMonth: String?
    private var period: AdminMonth { AdminMonth(selectedMonth ?? model.statistics?.period.month) }
    private var requestKey: String { "\(selectedMonth ?? "current"):\(auth.adminRevision)" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("RESUMEN DE LA PLATAFORMA")
                        .font(LoginStyle.font(10, bold: true, relativeTo: .caption)).tracking(2)
                        .foregroundStyle(LoginStyle.teal)
                    Text("Cuentas actuales y reservas del mes seleccionado.")
                        .font(LoginStyle.font(15)).foregroundStyle(LoginStyle.muted)
                    periodSelector
                    if model.isLoading {
                        ProgressView("Cargando estadísticas…").frame(maxWidth: .infinity).padding(40)
                    } else if let error = model.error {
                        AdminRetryView(message: error) { Task { await load() } }
                    } else if let stats = model.statistics {
                        statistics(stats)
                    }
                }
                .padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .background(LoginStyle.cream.ignoresSafeArea())
            .navigationTitle("Inicio")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(model.isLoading).accessibilityLabel("Actualizar estadísticas")
                }
            }
            .task(id: requestKey) { await load() }
            .refreshable { await load() }
        }
        .tint(LoginStyle.teal)
        .preferredColorScheme(.light)
    }

    private var periodSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mes de estadísticas").font(LoginStyle.font(13, bold: true, relativeTo: .footnote))
            HStack {
                Picker("Mes", selection: Binding(get: { period.month }, set: {
                    selectedMonth = AdminMonth(year: period.year, month: $0).value
                })) {
                    ForEach(1...12, id: \.self) { month in Text(AdminMonth.names[month - 1]).tag(month) }
                }
                Picker("Año", selection: Binding(get: { period.year }, set: {
                    selectedMonth = AdminMonth(year: $0, month: period.month).value
                })) {
                    ForEach(2000...2099, id: \.self) { year in Text(String(year)).tag(year) }
                }
                Spacer(minLength: 0)
            }
            .pickerStyle(.menu)
        }
        .foregroundStyle(LoginStyle.ink)
    }

    @ViewBuilder
    private func statistics(_ stats: AdminStatistics) -> some View {
        Text("Cuentas actuales").font(LoginStyle.font(20, bold: true, relativeTo: .title2))
            .foregroundStyle(LoginStyle.ink).accessibilityAddTraits(.isHeader)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
            metric("Negocios", value: stats.accounts.businesses, detail: "\(stats.accounts.activeBusinesses) activos")
            metric("Clientes", value: stats.accounts.clients, detail: "\(stats.accounts.activeClients) activos")
            metric("Correos verificados", value: stats.accounts.verifiedClients, detail: "Cuentas de clientes")
            metric("Servicios activos", value: stats.accounts.activeServices, detail: "Publicados por negocios")
        }
        Text("Reservas de \(AdminMonth.names[AdminMonth(stats.period.month).month - 1].lowercased()) \(String(stats.period.year))")
            .font(LoginStyle.font(20, bold: true, relativeTo: .title2))
            .foregroundStyle(LoginStyle.ink).accessibilityAddTraits(.isHeader)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
            metric("Reservas", value: stats.bookings.total)
            metric("Aceptadas", value: stats.bookings.accepted)
            metric("Completadas", value: stats.bookings.completed)
            metric("Pendientes", value: stats.bookings.pending)
            metric("Canceladas", value: stats.bookings.canceled)
            metric("No asistieron", value: stats.bookings.noShow)
        }
        Text("Sin apartados de pago pendientes. Zona horaria: \(stats.period.timezone).")
            .font(LoginStyle.font(12, relativeTo: .caption)).foregroundStyle(LoginStyle.muted)

        VStack(alignment: .leading, spacing: 18) {
            Text("Negocios con más reservas")
                .font(LoginStyle.font(18, bold: true, relativeTo: .headline)).accessibilityAddTraits(.isHeader)
            if stats.topBusinesses.isEmpty {
                Text("No hay reservas en el mes seleccionado.").foregroundStyle(LoginStyle.muted)
            }
            ForEach(Array(stats.topBusinesses.enumerated()), id: \.element.id) { index, business in
                VStack(alignment: .leading, spacing: 8) {
                    if auth.authenticatedSession?.user.allows(route: "/customers") == true {
                        NavigationLink {
                            AdminDetailView(kind: .businesses, id: business.ownerId, auth: auth)
                        } label: { rankingLabel(business, index: index) }
                    } else { rankingLabel(business, index: index) }
                    ProgressView(value: min(1, max(0, Double(business.bookingCount) / Double(max(stats.topBusinesses.first?.bookingCount ?? 1, 1)))))
                        .accessibilityLabel("\(business.name): \(business.bookingCount) reservas")
                }
            }
        }
        .font(LoginStyle.font(14)).foregroundStyle(LoginStyle.ink)
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(LoginStyle.line, lineWidth: 1))
        Text("Actualizado: \(adminDate(stats.generatedAt))")
            .font(LoginStyle.font(12, relativeTo: .caption)).foregroundStyle(LoginStyle.muted)
    }

    private func rankingLabel(_ business: AdminStatistics.TopBusiness, index: Int) -> some View {
        HStack(alignment: .top) {
            Text("\(index + 1). \(business.name)").foregroundStyle(LoginStyle.teal)
            Spacer()
            Text("\(business.bookingCount) reservas").foregroundStyle(LoginStyle.muted)
        }
    }

    private func metric(_ title: String, value: Int, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(LoginStyle.font(14)).foregroundStyle(LoginStyle.muted)
            Text(String(value)).font(LoginStyle.font(30, bold: true, relativeTo: .title)).foregroundStyle(LoginStyle.ink)
            if let detail { Text(detail).font(LoginStyle.font(12, relativeTo: .caption)).foregroundStyle(LoginStyle.muted) }
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .padding(18).background(.white).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(LoginStyle.line, lineWidth: 1))
    }

    private func load() async { await model.load(month: selectedMonth, auth: auth) }
}
