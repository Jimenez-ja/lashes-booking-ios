import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

private enum BusinessSection: String, CaseIterable { case profile = "Perfil", hours = "Horarios", policies = "Políticas" }

struct CompanyEditorView: View {
    let auth: LoginModel
    @State private var model: CompanyEditorModel
    @State private var section: BusinessSection = .profile
    @State private var isImporting = false
    @State private var editingHour: HourDraft?
    @State private var removingDay: Int?
    @State private var showsHelp = false
    @State private var showsShare = false
    @State private var showsSaved = false
    @FocusState private var isEditing: Bool
    init(auth: LoginModel) {
        self.auth = auth
        _model = State(initialValue: CompanyEditorModel(request: businessRequest(auth)))
    }
    var body: some View {
        NavigationStack {
            ZStack {
                if let error = model.loadError { AdminRetryView(message: error) { Task { await model.load() } } }
                else if model.hasLoaded { editor }
                else { ProgressView("Cargando negocio…") }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LoginStyle.cream.ignoresSafeArea())
            .navigationTitle("Mi negocio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button { showsHelp = true } label: { Image(systemName: "questionmark.circle") }.accessibilityLabel("Guía para empresas") }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Listo") { isEditing = false } }
            }
            .task { if !model.hasLoaded { await model.load() } }
            .safeAreaInset(edge: .bottom) { if model.hasLoaded { saveBar } }
            .sheet(item: $editingHour) { hour in
                BusinessHourEditor(hour: hour, availableDays: model.draft.hours.filter { !$0.enabled || $0.day == hour.day }.map(\.day)) { updated in
                    model.draft.hours[updated.day] = updated
                }
            }
            .confirmationDialog("¿Eliminar este horario?", isPresented: Binding(get: { removingDay != nil }, set: { if !$0 { removingDay = nil } }), titleVisibility: .visible) {
                if let day = removingDay { Button("Eliminar horario", role: .destructive) { model.draft.hours[day].enabled = false; removingDay = nil } }
                Button("Cancelar", role: .cancel) { removingDay = nil }
            } message: { Text("Tus clientes no podrán reservar ese día después de guardar los cambios.") }
            .sheet(isPresented: $showsHelp) { BusinessGuideView() }
            .sheet(isPresented: $showsShare) { if let id = model.draft.companyId { BusinessShareView(companyID: id) } }
            .alert("Cambios guardados", isPresented: $showsSaved) { Button("Listo", role: .cancel) {} } message: { Text("Tu perfil, horarios y políticas se actualizaron correctamente.") }
        }
        .tint(LoginStyle.teal).preferredColorScheme(.light)
    }
    private var editor: some View {
        VStack(spacing: 0) {
            Picker("Configuración", selection: $section) { ForEach(BusinessSection.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).padding(.horizontal, 20).padding(.vertical, 12)
            Form {
                if section == .profile { profile }
                if section == .hours { hours }
                if section == .policies { policies }
            }
            .scrollDismissesKeyboard(.interactively).scrollContentBackground(.hidden)
            .font(LoginStyle.font(16)).foregroundStyle(LoginStyle.ink)
        }
        .disabled(model.isSaving)
    }
    private var profile: some View {
        Group {
            Section {
                if let id = model.draft.companyId {
                    NavigationLink { BusinessPublicProfileView(auth: auth, companyID: id) } label: { Label("Ver perfil público", systemImage: "eye") }
                    Button { showsShare = true } label: { Label("Compartir negocio y QR", systemImage: "square.and.arrow.up") }
                } else { Text("Completa y guarda tu negocio para ver y compartir tu perfil público.").font(.footnote).foregroundStyle(LoginStyle.muted) }
            } footer: { Text("El perfil público muestra los datos guardados. Guarda tus cambios antes de revisarlo.") }
            Section("Imágenes de tu perfil") {
                BusinessPhotoField(title: "Portada", image: $model.draft.bannerImage, isImporting: $isImporting)
                BusinessPhotoField(title: "Foto de perfil", image: $model.draft.profileImage, isImporting: $isImporting)
            }
            Section("Información del negocio") {
                labeledField("Nombre del negocio", text: $model.draft.name)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Descripción").font(.footnote).foregroundStyle(LoginStyle.muted)
                    TextField("Cuéntales a tus clientes qué ofreces", text: $model.draft.description, axis: .vertical).lineLimit(4...6).focused($isEditing)
                        .onChange(of: model.draft.description) { _, text in if text.count > 300 { model.draft.description = String(text.prefix(300)) } }
                    Text("\(model.draft.description.count)/300").font(.caption).foregroundStyle(LoginStyle.muted).frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            Section("Ubicación") {
                labeledField("Estado", text: $model.draft.state, limit: 200)
                labeledField("Municipio", text: $model.draft.city, limit: 200)
                labeledField("Colonia", text: $model.draft.neighborhood, limit: 200)
            }
        }
    }
    private func labeledField(_ title: String, text: Binding<String>, limit: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote).foregroundStyle(LoginStyle.muted)
            TextField(title, text: text).focused($isEditing).textInputAutocapitalization(.sentences)
                .onChange(of: text.wrappedValue) { _, value in if let limit, value.count > limit { text.wrappedValue = String(value.prefix(limit)) } }
        }.padding(.vertical, 3)
    }
    private var hours: some View {
        Group {
            Section {
                Label("\(model.draft.hours.filter(\.enabled).count) días de atención", systemImage: "clock")
                Text("Define los días en que atiendes. Los clientes solo podrán reservar dentro de estos horarios.").font(.footnote).foregroundStyle(LoginStyle.muted)
                Menu {
                    ForEach(model.draft.hours.filter { !$0.enabled }) { hour in
                        Button(HourDraft.names[hour.day]) { editingHour = hour }
                    }
                } label: { Label("Agregar horario", systemImage: "plus.circle") }
                .disabled(model.draft.hours.allSatisfy(\.enabled))
            }
            Section {
                ForEach(model.draft.hours.filter(\.enabled)) { hour in
                    HStack {
                        Button { editingHour = hour } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(HourDraft.names[hour.day]).fontWeight(.semibold)
                                Text("\(hour.open.prefix(5)) – \(hour.close.prefix(5))").font(.subheadline).foregroundStyle(LoginStyle.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.borderless).accessibilityLabel("Editar horario de \(HourDraft.names[hour.day])")
                        Button { removingDay = hour.day } label: { Image(systemName: "trash").frame(width: 44, height: 44).foregroundStyle(.red) }
                            .buttonStyle(.borderless).accessibilityLabel("Eliminar horario de \(HourDraft.names[hour.day])")
                    }
                }
                if !model.draft.hours.contains(where: \.enabled) { Text("Sin horarios. Agrega al menos un día para recibir reservas.").foregroundStyle(LoginStyle.muted) }
            } header: { Text("Horario semanal") } footer: { Text("Toca un horario para editarlo. Los días que no agregues permanecerán cerrados.") }
        }
    }
    private var policies: some View {
        Group {
            Section {
                Text("Estas reglas se muestran a tus clientes y se aplican al cancelar o reagendar desde su cuenta.").font(.subheadline).foregroundStyle(LoginStyle.muted)
                Toggle("Permitir cancelación en línea", isOn: $model.draft.allowClientCancellation)
                Toggle("Permitir reagendar en línea", isOn: $model.draft.allowClientReschedule)
            } header: { Text("Cambios de citas") }
            Section {
                HStack {
                    Text("Horas de anticipación")
                    Spacer()
                    TextField("24", value: $model.draft.cancellationNoticeHours, format: .number.grouping(.never))
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 70).focused($isEditing)
                }
                Stepper("\(model.draft.cancellationNoticeHours) horas", value: $model.draft.cancellationNoticeHours, in: 0...168)
                Text("Entre 0 y 168 horas (7 días). Se aplica a los cambios en línea que permitas.").font(.footnote).foregroundStyle(LoginStyle.muted)
            } header: { Text("Anticipación mínima") }
            Section { Label("Las citas con pago requieren contactar al negocio para gestionar cancelaciones y posibles reembolsos.", systemImage: "info.circle").font(.footnote).foregroundStyle(LoginStyle.muted) }
        }
    }
    private var saveBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = model.error { Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.red).accessibilityAddTraits(.updatesFrequently) }
            Button {
                isEditing = false
                Task { await model.save(auth: auth); if model.notice != nil { showsSaved = true } }
            } label: {
                HStack { if model.isSaving { ProgressView().tint(.white) }; Text(model.isSaving ? "Guardando…" : "Guardar cambios").fontWeight(.semibold) }
                    .frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.borderedProminent).disabled(isImporting || model.isSaving)
        }.padding(.horizontal, 20).padding(.vertical, 12).background(.regularMaterial)
    }
}

private struct BusinessHourEditor: View {
    @State var hour: HourDraft
    let availableDays: [Int]
    let onSave: (HourDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    private var valid: Bool { if let open = clockSeconds(hour.open), let close = clockSeconds(hour.close) { return close > open }; return false }
    var body: some View {
        NavigationStack {
            Form {
                Picker("Día", selection: $hour.day) { ForEach(availableDays, id: \.self) { Text(HourDraft.names[$0]).tag($0) } }.disabled(hour.enabled)
                ClockField(title: "Apertura", text: $hour.open)
                ClockField(title: "Cierre", text: $hour.close)
                if !valid { Text("El cierre debe ser posterior a la apertura del mismo día.").foregroundStyle(.red) }
            }
            .navigationTitle(hour.enabled ? "Editar horario" : "Agregar horario").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { hour.enabled = true; onSave(hour); dismiss() }.disabled(!valid) }
            }
        }.tint(LoginStyle.teal).presentationDetents([.medium, .large])
    }
}

struct ClockField: View {
    let title: String
    @Binding var text: String
    var body: some View {
        DatePicker(title, selection: Binding(get: {
            let value = clockSeconds(text) ?? 0
            return Calendar.current.date(bySettingHour: value / 3600, minute: value / 60 % 60, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            text = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        }), displayedComponents: .hourAndMinute).environment(\.locale, Locale(identifier: "es_MX"))
    }
}

private struct BusinessPublicProfileView: View {
    let auth: LoginModel
    let companyID: String
    @State private var company: BusinessCompany?
    @State private var error: String?
    var body: some View {
        ZStack {
            if let error { AdminRetryView(message: error) { Task { await load() } } }
            else if let company {
                List {
                    Section {
                        BusinessPhotoPreview(image: company.bannerImageURL.map { BusinessImage(url: $0) })
                        BusinessPhotoPreview(image: company.profileImageURL.map { BusinessImage(url: $0) }).frame(width: 130).clipShape(Circle()).frame(maxWidth: .infinity)
                        Text(company.name ?? "Mi negocio").font(.title2.bold())
                        Text(company.description ?? "")
                        Label([company.neighborhood, company.city, company.state].compactMap { $0 }.joined(separator: ", "), systemImage: "mappin.and.ellipse")
                    }
                    Section("Servicios publicados") {
                        ForEach(company.services ?? []) { service in
                            VStack(alignment: .leading, spacing: 6) { Text(service.name).fontWeight(.semibold); Text(service.description ?? ""); Text("\(service.price.currency) · \(serviceMinutes(service.time ?? "")) min").foregroundStyle(LoginStyle.muted) }
                        }
                        if company.services?.isEmpty != false { Text("Aún no hay servicios publicados.") }
                    }
                    Section("Horarios de atención") {
                        ForEach((company.companyHours ?? []).filter { (0...6).contains($0.day) }, id: \.day) { hour in
                            LabeledContent(HourDraft.names[hour.day], value: "\(hour.open.prefix(5)) – \(hour.close.prefix(5))")
                        }
                    }
                    Section("Políticas de citas") {
                        LabeledContent("Cancelación en línea", value: company.allowClientCancellation == true ? "Permitida" : "No permitida")
                        LabeledContent("Reagendar en línea", value: company.allowClientReschedule == true ? "Permitido" : "No permitido")
                        LabeledContent("Anticipación mínima", value: "\(company.cancellationNoticeHours ?? 24) horas")
                    }
                }.scrollContentBackground(.hidden)
            } else { ProgressView("Cargando perfil público…") }
        }.background(LoginStyle.cream).navigationTitle("Perfil público").navigationBarTitleDisplayMode(.inline)
            .task { await load() }
    }
    private func load() async {
        error = nil
        do { let data = try await auth.authorizedData(path: "company/\(companyID)"); company = try JSONDecoder().decode(CompanyResponse.self, from: data).data }
        catch { self.error = adminErrorMessage(error) }
    }
}

private struct BusinessShareView: View {
    let companyID: String
    private let qr: UIImage?
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    private var url: URL { URL(string: "https://gestiq.app/store/\(companyID)")! }
    init(companyID: String) {
        self.companyID = companyID
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data("https://gestiq.app/store/\(companyID)".utf8); filter.correctionLevel = "H"
        if let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)), let cg = CIContext().createCGImage(output, from: output.extent) {
            qr = UIImage(cgImage: cg)
        } else { qr = nil }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let qr { Image(uiImage: qr).interpolation(.none).resizable().scaledToFit().padding(16).background(.white).accessibilityLabel("Código QR del perfil público") }
                    Text("Tus clientes pueden escanear este QR para ver tus servicios y reservar.").font(.subheadline)
                }
                Section {
                    ShareLink(item: url) { Label("Compartir enlace", systemImage: "square.and.arrow.up") }
                    Button { UIPasteboard.general.url = url; copied = true } label: { Label(copied ? "Enlace copiado" : "Copiar enlace", systemImage: "doc.on.doc") }
                    if let qr { ShareLink(item: Image(uiImage: qr), preview: SharePreview("QR de mi negocio", image: Image(uiImage: qr))) { Label("Compartir o guardar QR", systemImage: "qrcode") } }
                }
            }.navigationTitle("Compartir negocio").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
        }.tint(LoginStyle.teal)
    }
}

private struct BusinessGuideView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Perfil") { Text("Completa tu nombre, descripción y ubicación. Agrega portada y foto de perfil para que tus clientes reconozcan tu negocio.") }
                Section("Horarios") { Text("Agrega los días y horas en que atiendes. Toca un horario para editarlo o usa la papelera para quitarlo. Guarda los cambios para actualizar los espacios disponibles.") }
                Section("Servicios y anticipos") { Text("En Servicios, define qué incluye cada servicio, su precio, duración y fotos. Los anticipos son opcionales y requieren una cuenta de Mercado Pago vinculada; no pueden superar el precio con descuento del servicio o del retoque.") }
                Section("Comparte tu negocio") { Text("Guarda tus cambios y revisa Ver perfil público. En Compartir negocio y QR puedes copiar el enlace o enviar el QR con el menú nativo de compartir.") }
                Section("Cambios de citas") { Text("En Políticas, permite cancelaciones o cambios de fecha y define la anticipación mínima. Las citas con pago requieren contactar al negocio para gestionar cancelaciones y posibles reembolsos.") }
            }.navigationTitle("Guía para empresas").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
        }.tint(LoginStyle.teal)
    }
}
