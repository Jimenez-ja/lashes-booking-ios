import SwiftUI

struct BusinessServicesView: View {
    let auth: LoginModel
    @State private var model: BusinessServicesModel
    @State private var search = ""
    @State private var page = 1
    @State private var showsCreate = false
    private var requestKey: String { "\(page):\(search):\(auth.businessRevision)" }
    init(auth: LoginModel) {
        self.auth = auth
        _model = State(initialValue: BusinessServicesModel(request: businessRequest(auth)))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.isLoading { ProgressView("Cargando servicios…").frame(maxWidth: .infinity).padding(40) }
                    else if let error = model.error { AdminRetryView(message: error) { Task { await load() } } }
                    else if model.services.isEmpty {
                        ContentUnavailableView("Sin servicios", systemImage: "list.bullet.rectangle",
                            description: Text(search.isEmpty ? "Crea tu primer servicio para ofrecer reservas." : "Prueba con otra búsqueda."))
                        if search.isEmpty { Button("Crear servicio") { showsCreate = true }.buttonStyle(.borderedProminent) }
                    } else {
                        if let pagination = model.pagination {
                            Text("\(pagination.totalItems) servicios").font(LoginStyle.font(14, bold: true)).foregroundStyle(LoginStyle.teal)
                        }
                        LazyVStack(spacing: 12) {
                            ForEach(model.services) { service in
                                NavigationLink {
                                    ServiceEditorView(auth: auth, serviceId: service.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack { Text(service.name).font(LoginStyle.font(18, bold: true)); Spacer(); Image(systemName: "chevron.right") }
                                        Text("\(service.price.currency) · \(serviceMinutes(service.time ?? "")) min")
                                            .font(LoginStyle.font(15)).foregroundStyle(LoginStyle.muted)
                                        Text(service.status?.canonicalName == "active" ? "Publicado" : "Archivado")
                                            .font(LoginStyle.font(12, relativeTo: .caption)).foregroundStyle(LoginStyle.teal)
                                    }
                                    .foregroundStyle(LoginStyle.ink)
                                    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.white).clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(LoginStyle.line, lineWidth: 1))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    if let pagination = model.pagination, pagination.totalPages > 1 {
                        HStack {
                            Button("Anterior") { page -= 1 }.disabled(page <= 1)
                            Spacer(); Text("\(page) de \(pagination.totalPages)").font(.footnote); Spacer()
                            Button("Siguiente") { page += 1 }.disabled(page >= pagination.totalPages)
                        }
                    }
                }.padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .background(LoginStyle.cream.ignoresSafeArea())
            .navigationTitle("Servicios")
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button { showsCreate = true } label: { Image(systemName: "plus") }.accessibilityLabel("Crear servicio")
            } }
            .searchable(text: $search, prompt: "Buscar servicios")
            .onChange(of: search) { _, text in page = 1; if text.count > 100 { search = String(text.prefix(100)) } }
            .task(id: requestKey) {
                if !search.isEmpty { do { try await Task.sleep(for: .milliseconds(300)) } catch { return } }
                await load()
            }
            .refreshable { await load() }
            .sheet(isPresented: $showsCreate) { NavigationStack { ServiceEditorView(auth: auth, serviceId: nil) } }
        }
        .tint(LoginStyle.teal).preferredColorScheme(.light)
    }
    private func load() async { await model.load(page: page, search: search) }
}

struct ServiceEditorView: View {
    let auth: LoginModel
    @State private var model: ServiceEditorModel
    @State private var isImporting = false
    @State private var confirmsStatus = false
    @Environment(\.dismiss) private var dismiss
    init(auth: LoginModel, serviceId: String?) {
        self.auth = auth
        _model = State(initialValue: ServiceEditorModel(serviceId: serviceId, request: businessRequest(auth)))
    }
    var body: some View {
        ZStack {
            if let error = model.loadError { AdminRetryView(message: error) { Task { await model.load() } } }
            else if model.hasLoaded { editor }
            else { ProgressView("Cargando servicio…") }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LoginStyle.cream.ignoresSafeArea())
        .navigationTitle(model.serviceId == nil ? "Nuevo servicio" : "Editar servicio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if model.serviceId == nil { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(model.isSaving) } } }
        .task { if !model.hasLoaded { await model.load() } }
        .alert("Servicio guardado", isPresented: Binding(get: { model.saved }, set: { _ in })) {
            Button("Listo") { dismiss() }
        } message: { Text("Los cambios ya están registrados en tu negocio.") }
        .confirmationDialog(statusTitle, isPresented: $confirmsStatus, titleVisibility: .visible) {
            Button(statusTitle, role: model.service?.status?.canonicalName == "active" ? .destructive : nil) {
                Task { await model.changeStatus(auth: auth) }
            }
            Button("Cancelar", role: .cancel) {}
        }
        .tint(LoginStyle.teal).preferredColorScheme(.light)
    }
    private var statusTitle: String { model.service?.status?.canonicalName == "active" ? "Archivar servicio" : "Publicar servicio" }
    private var editor: some View {
        Form {
            if let error = model.error { Section { Text(error).foregroundStyle(.red) } }
            Section("Datos del servicio") {
                TextField("Nombre", text: $model.draft.name)
                TextField("Descripción", text: $model.draft.description, axis: .vertical).lineLimit(3...6)
                BusinessAmountField(title: "Precio (MXN)", text: $model.draft.price)
                HStack { Text("Duración (minutos)"); Spacer(); TextField("45", text: $model.draft.minutes).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                Text("Incluye el tiempo necesario para atender al cliente.").font(.footnote).foregroundStyle(LoginStyle.muted)
            }
            Section("Fotos") { ServicePhotosField(images: $model.draft.images, isImporting: $isImporting) }
            Section("Opciones de precio") {
                Stepper("Descuento: \(model.draft.discount)%", value: $model.draft.discount, in: 0...100)
                Toggle("Ofrecer retoque", isOn: $model.draft.retouch)
                if model.draft.retouch {
                    BusinessAmountField(title: "Precio del retoque (MXN)", text: $model.draft.priceRetouch)
                    Stepper("Descuento del retoque: \(model.draft.discountRetouch)%", value: $model.draft.discountRetouch, in: 0...100)
                }
                Toggle("Pedir anticipo", isOn: $model.draft.advance)
                    .disabled(auth.authenticatedSession?.user.mercadoPagoPublicKey?.isEmpty != false && !model.draft.advance)
                if auth.authenticatedSession?.user.mercadoPagoPublicKey?.isEmpty != false {
                    Text("Para habilitar anticipos necesitas una cuenta de Mercado Pago vinculada.").font(.footnote).foregroundStyle(LoginStyle.muted)
                }
                if model.draft.advance { BusinessAmountField(title: "Anticipo (MXN)", text: $model.draft.advancePrice) }
            }
            Section("Extras opcionales") {
                ForEach($model.draft.extras) { $extra in
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Nombre del extra", text: $extra.name)
                        BusinessAmountField(title: "Precio (MXN)", text: $extra.price)
                        if model.draft.retouch { BusinessAmountField(title: "Precio en retoque (opcional)", text: $extra.priceRetouch) }
                        Button("Quitar extra", role: .destructive) { model.draft.extras.removeAll { $0.id == extra.id } }
                            .buttonStyle(.borderless)
                    }.padding(.vertical, 8)
                }
                Button { model.draft.extras.append(ExtraDraft()) } label: { Label("Agregar extra", systemImage: "plus") }
                    .disabled(model.draft.extras.count >= 30)
            }
            Section {
                Button { Task { await model.save(auth: auth) } } label: {
                    HStack { if model.isSaving { ProgressView() }; Text(model.isSaving ? "Guardando…" : "Guardar servicio") }
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent).disabled(isImporting || model.isSaving)
                if model.serviceId != nil {
                    Button(statusTitle, role: model.service?.status?.canonicalName == "active" ? .destructive : nil) { confirmsStatus = true }
                        .disabled(isImporting || model.isSaving)
                }
            }
        }
        .disabled(model.isSaving)
        .font(LoginStyle.font(16)).foregroundStyle(LoginStyle.ink).scrollContentBackground(.hidden)
    }
}

struct BusinessAmountField: View {
    let title: String
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote).foregroundStyle(LoginStyle.muted)
            TextField("0.00", text: $text).keyboardType(.decimalPad)
                .accessibilityLabel(title)
        }
    }
}
