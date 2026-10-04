import Foundation

struct BusinessMoney: Codable, Equatable {
    let value: Double
    init(_ value: Double) { self.value = value }
    init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if let number = try? box.decode(Double.self) { value = number }
        else {
            let text = try box.decode(String.self)
            guard let number = Double(text), number.isFinite else {
                throw DecodingError.dataCorruptedError(in: box, debugDescription: "Invalid amount")
            }
            value = number
        }
    }
    func encode(to encoder: Encoder) throws {
        var box = encoder.singleValueContainer(); try box.encode(value)
    }
    var text: String { NSDecimalNumber(value: value).stringValue }
    var currency: String { value.formatted(.currency(code: "MXN")) }
}

struct BusinessImage: Codable, Identifiable {
    private var localID = UUID().uuidString
    var fileId: String?
    var name: String?
    var url: String?
    var base64: String?
    var isNew: Bool?
    var deleted: Bool?
    var id: String { fileId ?? localID }
    init(fileId: String? = nil, name: String? = nil, url: String? = nil, base64: String? = nil, isNew: Bool? = nil, deleted: Bool? = nil) {
        self.fileId = fileId; self.name = name; self.url = url; self.base64 = base64; self.isNew = isNew; self.deleted = deleted
    }
    enum CodingKeys: String, CodingKey { case fileId, name, url, base64, isNew, deleted }
    var isPresent: Bool { deleted != true && (base64?.isEmpty == false || url?.isEmpty == false) }
}

struct CompanyHour: Codable { let companyHourId: String?; let day: Int; let open: String; let close: String }
struct BusinessCompany: Decodable {
    let companyId: String
    let name: String?; let description: String?; let state: String?; let city: String?; let neighborhood: String?
    let profileImageURL: String?; let bannerImageURL: String?
    let cancellationNoticeHours: Int?; let allowClientCancellation: Bool?; let allowClientReschedule: Bool?
    let companyHours: [CompanyHour]?
    let services: [BusinessService]?
}
struct CompanyResponse: Decodable { let data: BusinessCompany }
struct CompanyHourWrite: Encodable {
    let companyHourId: String?; let day: Int; let open: String; let close: String; let isNew: Bool; let deleted: Bool
}
struct CompanyWrite: Encodable {
    let name: String; let description: String; let state: String; let municipality: String; let neighborhood: String
    let profileImage: BusinessImage; let bannerImage: BusinessImage; let shopHours: [CompanyHourWrite]
    let cancellationNoticeHours: Int; let allowClientCancellation: Bool; let allowClientReschedule: Bool
}
struct HourDraft: Identifiable {
    var day: Int
    var enabled = false
    var open = "09:00"
    var close = "18:00"
    var id: Int { day }
    static let names = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"]
}

struct CompanyDraft {
    var name = ""; var description = ""; var state = ""; var city = ""; var neighborhood = ""
    var profileImage: BusinessImage?; var bannerImage: BusinessImage?
    var cancellationNoticeHours = 24
    var allowClientCancellation = true; var allowClientReschedule = true
    var hours = (0...6).map { HourDraft(day: $0) }
    var originalHours: [CompanyHour] = []
    var companyId: String?

    init(company: BusinessCompany? = nil) {
        guard let company else { return }
        companyId = company.companyId
        name = company.name ?? ""; description = company.description ?? ""
        state = company.state ?? ""; city = company.city ?? ""; neighborhood = company.neighborhood ?? ""
        profileImage = company.profileImageURL.map { BusinessImage(name: "profile", url: $0, isNew: false) }
        bannerImage = company.bannerImageURL.map { BusinessImage(name: "banner", url: $0, isNew: false) }
        cancellationNoticeHours = company.cancellationNoticeHours ?? 24
        allowClientCancellation = company.allowClientCancellation ?? true
        allowClientReschedule = company.allowClientReschedule ?? true
        originalHours = company.companyHours ?? []
        for hour in originalHours where (0...6).contains(hour.day) {
            hours[hour.day].enabled = true; hours[hour.day].open = hour.open; hours[hour.day].close = hour.close
        }
    }

    func payload() throws -> CompanyWrite {
        guard [name, description, state, city, neighborhood].allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw AuthError.message("Completa el nombre, descripción y ubicación del negocio.")
        }
        guard description.count <= 300 else { throw AuthError.message("La descripción admite hasta 300 caracteres.") }
        guard let profileImage, profileImage.isPresent, let bannerImage, bannerImage.isPresent else {
            throw AuthError.message("Agrega una foto de perfil y una portada.")
        }
        guard (0...168).contains(cancellationNoticeHours) else { throw AuthError.message("La anticipación debe estar entre 0 y 168 horas.") }
        guard hours.contains(where: \.enabled) else { throw AuthError.message("Agrega al menos un día de atención.") }
        var writes: [CompanyHourWrite] = []
        for hour in hours {
            let original = originalHours.first { $0.day == hour.day }
            if hour.enabled {
                guard let open = clockSeconds(hour.open), let close = clockSeconds(hour.close), close > open else {
                    throw AuthError.message("\(HourDraft.names[hour.day]): el cierre debe ser posterior a la apertura del mismo día.")
                }
            }
            let changed = original.map { $0.open != hour.open || $0.close != hour.close } ?? true
            if let original, !hour.enabled || changed {
                writes.append(CompanyHourWrite(companyHourId: original.companyHourId, day: original.day,
                    open: original.open, close: original.close, isNew: false, deleted: true))
            }
            if hour.enabled {
                writes.append(CompanyHourWrite(companyHourId: changed ? nil : original?.companyHourId,
                    day: hour.day, open: hour.open, close: hour.close, isNew: changed, deleted: false))
            }
        }
        return CompanyWrite(name: name.trimmingCharacters(in: .whitespacesAndNewlines), description: description,
            state: state, municipality: city, neighborhood: neighborhood, profileImage: profileImage,
            bannerImage: bannerImage, shopHours: writes, cancellationNoticeHours: cancellationNoticeHours,
            allowClientCancellation: allowClientCancellation, allowClientReschedule: allowClientReschedule)
    }
}

func clockSeconds(_ text: String) -> Int? {
    let rawParts = text.split(separator: ":", omittingEmptySubsequences: false)
    let parts = rawParts.compactMap { Int($0) }
    guard parts.count == rawParts.count else { return nil }
    guard (2...3).contains(parts.count), (0...23).contains(parts[0]), (0...59).contains(parts[1]),
          parts.count == 2 || (0...59).contains(parts[2]) else { return nil }
    return parts[0] * 3600 + parts[1] * 60 + (parts.count == 3 ? parts[2] : 0)
}

struct ServiceExtra: Codable, Identifiable, Equatable {
    let extraId: String; let name: String; let price: BusinessMoney; let priceRetouch: BusinessMoney?
    var id: String { extraId }
}
struct BusinessService: Decodable, Identifiable {
    let serviceId: String; let name: String; let description: String?; let time: String?
    let price: BusinessMoney; let discount: Int?
    let retouch: Bool?; let priceRetouch: BusinessMoney?; let discountRetouch: Int?
    let advance: Bool?; let advancePrice: BusinessMoney?
    let statusId: String?; let status: AdminStatus?
    let images: [BusinessImage]?; let relServiceExtras: [ServiceExtra]?
    var id: String { serviceId }
}
struct ServiceResponse: Decodable { let data: BusinessService }
struct ServiceListResponse: Decodable { let data: [BusinessService]; let pagination: AdminPagination }
struct ExtraDraft: Identifiable {
    var id = UUID().uuidString
    var extraId: String?
    var name = ""; var price = ""; var priceRetouch = ""
}
struct ExtraWrite: Encodable {
    let extraId: String?; let name: String; let price: Double; let priceRetouch: Double?
    let isNew: Bool; let deleted: Bool
}
struct ServiceWrite: Encodable {
    let name: String; let description: String; let price: Double; let time: String; let discount: Int
    let retouch: Bool; let priceRetouch: Double?; let discountRetouch: Int?
    let advance: Bool; let advancePrice: Double?
    let images: [BusinessImage]; let extras: [ExtraWrite]
    enum CodingKeys: String, CodingKey { case name, description, price, time, discount, retouch, priceRetouch, discountRetouch, advance, advancePrice, images, extras }
    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(name, forKey: .name); try box.encode(description, forKey: .description)
        try box.encode(price, forKey: .price); try box.encode(time, forKey: .time); try box.encode(discount, forKey: .discount)
        try box.encode(retouch, forKey: .retouch); try box.encode(advance, forKey: .advance)
        if let priceRetouch { try box.encode(priceRetouch, forKey: .priceRetouch) } else { try box.encodeNil(forKey: .priceRetouch) }
        if let discountRetouch { try box.encode(discountRetouch, forKey: .discountRetouch) } else { try box.encodeNil(forKey: .discountRetouch) }
        if let advancePrice { try box.encode(advancePrice, forKey: .advancePrice) } else { try box.encodeNil(forKey: .advancePrice) }
        try box.encode(images, forKey: .images); try box.encode(extras, forKey: .extras)
    }
}

struct ServiceDraft {
    var serviceId: String?
    var name = ""; var description = ""; var price = ""; var minutes = "45"
    var discount = 0; var retouch = false; var priceRetouch = ""; var discountRetouch = 0
    var advance = false; var advancePrice = ""
    var images: [BusinessImage] = []; var extras: [ExtraDraft] = []; var originalExtras: [ServiceExtra] = []
    init(service: BusinessService? = nil) {
        guard let service else { return }
        serviceId = service.id; name = service.name; description = service.description ?? ""
        price = service.price.text; minutes = String(serviceMinutes(service.time ?? ""))
        discount = service.discount ?? 0; retouch = service.retouch ?? false
        priceRetouch = service.priceRetouch?.text ?? ""; discountRetouch = service.discountRetouch ?? 0
        advance = service.advance ?? false; advancePrice = service.advancePrice?.text ?? ""
        images = service.images ?? []; originalExtras = service.relServiceExtras ?? []
        extras = originalExtras.map { ExtraDraft(extraId: $0.extraId, name: $0.name, price: $0.price.text, priceRetouch: $0.priceRetouch?.text ?? "") }
    }
    func payload() throws -> ServiceWrite {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AuthError.message("Completa el nombre y la descripción del servicio.")
        }
        guard description.count <= 300 else { throw AuthError.message("La descripción admite hasta 300 caracteres.") }
        guard let duration = Int(minutes), (1...1440).contains(duration) else { throw AuthError.message("Usa una duración de 1 a 1440 minutos enteros.") }
        let priceValue = try validAmount(price, label: "Precio")
        guard (0...100).contains(discount), (0...100).contains(discountRetouch) else { throw AuthError.message("Los descuentos deben estar entre 0 y 100%.") }
        let retouchValue = retouch ? try validAmount(priceRetouch, label: "Precio del retoque") : nil
        let advanceValue = advance ? try validAmount(advancePrice, label: "Anticipo") : nil
        if let advanceValue {
            let totals = [priceValue * Double(100 - discount) / 100] + (retouchValue.map { [$0 * Double(100 - discountRetouch) / 100] } ?? [])
            guard (advanceValue * 100).rounded() > 0, totals.allSatisfy({ advanceValue <= ($0 * 100).rounded() / 100 }) else {
                throw AuthError.message("El anticipo debe ser mayor a cero y no superar el precio con descuento de ninguna modalidad.")
            }
        }
        guard (1...5).contains(images.filter(\.isPresent).count) else { throw AuthError.message("Agrega entre 1 y 5 fotos del servicio.") }
        guard extras.count <= 30 else { throw AuthError.message("Puedes agregar hasta 30 extras.") }
        var extraWrites: [ExtraWrite] = []
        for extra in extras {
            guard !extra.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AuthError.message("Todos los extras necesitan un nombre.") }
            let cost = try validAmount(extra.price, label: "Precio del extra")
            let retouchCost = retouch && !extra.priceRetouch.isEmpty ? try validAmount(extra.priceRetouch, label: "Precio del extra en retoque") : nil
            let original = originalExtras.first { $0.extraId == extra.extraId }
            let changed = original.map { $0.name != extra.name || $0.price.value != cost || $0.priceRetouch?.value != retouchCost } ?? true
            if let original, changed {
                extraWrites.append(ExtraWrite(extraId: original.extraId, name: original.name, price: original.price.value,
                    priceRetouch: original.priceRetouch?.value, isNew: false, deleted: true))
            }
            extraWrites.append(ExtraWrite(extraId: changed ? nil : extra.extraId, name: extra.name, price: cost,
                priceRetouch: retouchCost, isNew: changed, deleted: false))
        }
        for old in originalExtras where !extras.contains(where: { $0.extraId == old.extraId }) {
            extraWrites.append(ExtraWrite(extraId: old.extraId, name: old.name, price: old.price.value,
                priceRetouch: old.priceRetouch?.value, isNew: false, deleted: true))
        }
        guard extraWrites.count <= 30 else { throw AuthError.message("Realiza los cambios de extras en grupos más pequeños y guarda antes de continuar.") }
        let imageWrites = images.filter { serviceId == nil || $0.base64 != nil || $0.deleted == true }
        guard imageWrites.count <= 5 else { throw AuthError.message("Cambia las fotos en grupos más pequeños y guarda antes de continuar.") }
        return ServiceWrite(name: name.trimmingCharacters(in: .whitespacesAndNewlines), description: description, price: priceValue,
            time: "\(duration)m", discount: discount, retouch: retouch, priceRetouch: retouchValue,
            discountRetouch: retouch ? discountRetouch : nil, advance: advance, advancePrice: advanceValue,
            images: imageWrites, extras: extraWrites)
    }
}

func validAmount(_ raw: String, label: String) throws -> Double {
    guard let value = Double(raw.replacingOccurrences(of: ",", with: ".")), value.isFinite, value >= 0 else {
        throw AuthError.message("\(label): ingresa un importe válido, mayor o igual a cero.")
    }
    return (value * 100).rounded() / 100
}
func serviceMinutes(_ raw: String) -> Int {
    let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*([hm])"#
    let regex = try! NSRegularExpression(pattern: pattern)
    let matches = regex.matches(in: raw.lowercased(), range: NSRange(raw.startIndex..., in: raw))
    let text = raw.lowercased() as NSString
    let value = matches.reduce(0.0) { total, match in
        let amount = Double(text.substring(with: match.range(at: 1))) ?? 0
        return total + amount * (text.substring(with: match.range(at: 2)) == "h" ? 60 : 1)
    }
    return Int(value.rounded())
}
