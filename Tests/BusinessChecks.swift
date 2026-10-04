import Foundation

@main
@MainActor
struct BusinessChecks {
    static let companyData = Data(#"{"data":{"companyId":"company-1","name":"Negocio","description":"Descripción","state":"Estado","city":"Ciudad","neighborhood":"Centro","profileImageURL":"https://example.test/profile.jpg","bannerImageURL":"https://example.test/banner.jpg","companyHours":[{"companyHourId":"hour-1","day":0,"open":"09:00:00","close":"18:00:00"}]}}"#.utf8)
    static let serviceData = Data(#"{"data":{"serviceId":"service-1","name":"Servicio","description":"Descripción","price":"200.50","time":"1h 30m","discount":10,"retouch":true,"priceRetouch":"100.00","discountRetouch":0,"advance":true,"advancePrice":"50.00","status":{"name":"active"},"images":[{"fileId":"photo-1","url":"https://example.test/photo.jpg"}],"relServiceExtras":[{"extraId":"extra-1","name":"Extra","price":"20.00","priceRetouch":"10.00"}]}}"#.utf8)

    static func rejects(_ work: () throws -> Void) {
        do { try work(); preconditionFailure("Expected validation failure") } catch {}
    }

    static func main() async throws {
        let decoder = JSONDecoder()
        let company = try decoder.decode(CompanyResponse.self, from: companyData).data
        var publicCompany = try JSONSerialization.jsonObject(with: companyData) as! [String: Any]
        var publicData = publicCompany["data"] as! [String: Any]
        let serviceObject = try JSONSerialization.jsonObject(with: serviceData) as! [String: Any]
        publicData["services"] = [serviceObject["data"]!]
        publicCompany["data"] = publicData
        let publicProfile = try decoder.decode(CompanyResponse.self, from: JSONSerialization.data(withJSONObject: publicCompany)).data
        precondition(publicProfile.services?.first?.price.value == 200.5)
        var business = CompanyDraft(company: company)
        let unchanged = try business.payload()
        precondition(unchanged.shopHours.count == 1 && !unchanged.shopHours[0].isNew)
        precondition(unchanged.profileImage.isNew == false && unchanged.municipality == "Ciudad")
        business.hours[0].close = "17:00"
        let edited = try business.payload()
        precondition(edited.shopHours.count == 2 && edited.shopHours[0].deleted)
        precondition(edited.shopHours[0].companyHourId == "hour-1" && edited.shopHours[1].isNew)
        business.hours[1].enabled = true; business.hours[0].enabled = false
        let removed = try business.payload()
        precondition(removed.shopHours[0].deleted && removed.shopHours[1].day == 1)
        business.hours[1].close = "08:00"
        rejects { _ = try business.payload() }
        precondition(clockSeconds("09:30:59") == 34259 && clockSeconds("24:00") == nil)
        precondition(clockSeconds("09:x:30") == nil && clockSeconds("09::30") == nil)

        let service = try decoder.decode(ServiceResponse.self, from: serviceData).data
        precondition(service.price.value == 200.5 && serviceMinutes("1h 30m") == 90)
        var draft = ServiceDraft(service: service)
        let preserved = try draft.payload()
        precondition(preserved.images.isEmpty && preserved.time == "90m")
        precondition(preserved.extras.count == 1 && !preserved.extras[0].isNew)
        draft.extras[0].price = "25,50"
        let replaced = try draft.payload()
        precondition(replaced.extras.count == 2 && replaced.extras[0].deleted)
        precondition(replaced.extras[1].isNew && replaced.extras[1].price == 25.5)
        draft.extras = []
        let removedExtra = try draft.payload()
        precondition(removedExtra.extras[0].deleted)
        draft.advancePrice = "101"
        rejects { _ = try draft.payload() }
        draft.advancePrice = "0"
        rejects { _ = try draft.payload() }
        draft.advance = false; draft.retouch = false
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft.payload())) as! [String: Any]
        precondition(json["advancePrice"] is NSNull && json["priceRetouch"] is NSNull && json["discountRetouch"] is NSNull)
        draft.images[0].deleted = true
        rejects { _ = try draft.payload() }
        draft.images.append(BusinessImage(name: "new.jpg", base64: "ZmFrZQ==", isNew: true))
        let photos = try draft.payload().images
        precondition(photos.count == 2 && photos[0].deleted == true && photos[1].isNew == true)

        let auth = LoginModel()
        var writes = 0
        let editor = CompanyEditorModel { path, method, body, _ in
            if method == .get { precondition(path == "company/myself"); return companyData }
            precondition(path == "company" && method == .patch && body != nil)
            let json = try JSONSerialization.jsonObject(with: body!) as! [String: Any]
            precondition(json["companyId"] == nil && json["municipality"] as? String == "Ciudad")
            writes += 1; return companyData
        }
        await editor.load(); await editor.save(auth: auth)
        precondition(editor.notice != nil && writes == 1 && auth.businessRevision == 1)

        let missing = CompanyEditorModel { _, _, _, _ in throw AuthError.noCompany }
        await missing.load()
        precondition(missing.hasLoaded && missing.draft.companyId == nil && missing.loadError == nil)
        let outage = CompanyEditorModel { _, _, _, _ in throw URLError(.timedOut) }
        await outage.load(); await outage.save(auth: auth)
        precondition(!outage.hasLoaded && outage.loadError != nil)

        let create = CompanyEditorModel { path, method, _, _ in
            if method == .get { throw AuthError.noCompany }
            precondition(path == "company" && method == .post)
            return companyData
        }
        await create.load(); create.draft = CompanyDraft(company: company); create.draft.companyId = nil
        await create.save(auth: auth)
        precondition(create.draft.companyId == "company-1" && create.notice != nil)

        let services = ServiceEditorModel(serviceId: "service-1") { path, method, body, _ in
            if method == .get { precondition(path == "services/service-1"); return serviceData }
            precondition(method == .patch)
            if path == "services/changeStatus/service-1" { return Data(#"{"data":"service-1"}"#.utf8) }
            precondition(path == "services/service-1" && body != nil)
            return serviceData
        }
        await services.load(); await services.save(auth: auth)
        precondition(services.saved && services.error == nil)
        await services.changeStatus(auth: auth)
        precondition(auth.businessRevision == 4)

        let newService = ServiceEditorModel(serviceId: nil) { path, method, body, _ in
            precondition(path == "services" && method == .post && body != nil)
            return serviceData
        }
        await newService.load(); newService.draft = ServiceDraft(service: service)
        newService.draft.serviceId = nil
        await newService.save(auth: auth)
        precondition(newService.saved)
        let failed = ServiceEditorModel(serviceId: "service-1") { _, method, _, _ in
            if method == .get { return serviceData }
            throw URLError(.networkConnectionLost)
        }
        await failed.load(); await failed.save(auth: auth)
        precondition(!failed.saved && failed.error?.contains("confirmar") == true && !failed.isSaving)

        let list = BusinessServicesModel { path, method, _, query in
            precondition(path == "services" && method == .get)
            precondition(query.first { $0.name == "wildcard" }?.value == "a+b")
            return Data(#"{"data":[],"pagination":{"page":2,"pageSize":10,"totalItems":0,"totalPages":0}}"#.utf8)
        }
        await list.load(page: 2, search: " a+b ")
        precondition(list.error == nil && list.pagination?.page == 2)
        var pending: [String: CheckedContinuation<Data, Error>] = [:]
        let races = BusinessServicesModel { _, _, _, query in
            let search = query.first { $0.name == "wildcard" }!.value!
            return try await withCheckedThrowingContinuation { pending[search] = $0 }
        }
        let old = Task { await races.load(page: 1, search: "old") }
        while pending["old"] == nil { await Task.yield() }
        let new = Task { await races.load(page: 2, search: "new") }
        while pending["new"] == nil { await Task.yield() }
        pending["new"]!.resume(returning: Data(#"{"data":[],"pagination":{"page":2,"pageSize":10,"totalItems":0,"totalPages":0}}"#.utf8))
        await new.value
        pending["old"]!.resume(throwing: URLError(.timedOut))
        await old.value
        precondition(races.pagination?.page == 2 && races.error == nil && !races.isLoading)
        print("Business checks passed")
    }
}
