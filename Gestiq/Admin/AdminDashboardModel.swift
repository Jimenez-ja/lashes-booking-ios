import Foundation
import Observation

struct AdminStatistics: Decodable {
    struct Period: Decodable { let month: String; let year: Int; let timezone: String }
    struct Accounts: Decodable {
        let businesses: Int; let activeBusinesses: Int
        let clients: Int; let activeClients: Int
        let verifiedClients: Int; let activeServices: Int
    }
    struct Bookings: Decodable {
        let total: Int; let accepted: Int; let pending: Int
        let canceled: Int; let completed: Int; let noShow: Int
    }
    struct TopBusiness: Decodable, Identifiable {
        let companyId: String; let ownerId: String; let name: String; let bookingCount: Int
        var id: String { companyId }
    }
    let period: Period
    let generatedAt: String
    let accounts: Accounts
    let bookings: Bookings
    let topBusinesses: [TopBusiness]
}
struct StatisticsResponse: Decodable { let data: AdminStatistics }

struct AdminMonth {
    let year: Int
    let month: Int
    var value: String { String(format: "%04d-%02d", year, month) }
    static let names = ["Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio", "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"]

    init(year: Int, month: Int) { self.year = year; self.month = month }
    init(_ value: String?) {
        let parts = value?.split(separator: "-").compactMap { Int($0) } ?? []
        if parts.count == 2, (2000...2099).contains(parts[0]), (1...12).contains(parts[1]) {
            year = parts[0]; month = parts[1]
        } else {
            let calendar = Calendar(identifier: .gregorian)
            year = calendar.component(.year, from: Date())
            month = calendar.component(.month, from: Date())
        }
    }
}

@MainActor
@Observable
final class AdminDashboardModel {
    private(set) var statistics: AdminStatistics?
    private(set) var isLoading = false
    private(set) var error: String?
    private var generation = 0
    private let fetch: ((String, [URLQueryItem]) async throws -> Data)?

    init(fetch: ((String, [URLQueryItem]) async throws -> Data)? = nil) { self.fetch = fetch }

    func load(month: String?, auth: LoginModel) async {
        generation += 1
        let request = generation
        statistics = nil
        error = nil
        isLoading = true
        defer { if generation == request { isLoading = false } }
        do {
            let query = month.map { [URLQueryItem(name: "month", value: $0)] } ?? []
            let path = "bookings/admin/statistics"
            let data: Data
            if let fetch { data = try await fetch(path, query) }
            else { data = try await auth.authorizedData(path: path, query: query) }
            let result = try JSONDecoder().decode(StatisticsResponse.self, from: data).data
            guard request == generation, !Task.isCancelled else { return }
            statistics = result
        } catch {
            guard request == generation, !Task.isCancelled else { return }
            self.error = adminErrorMessage(error)
        }
    }
}
