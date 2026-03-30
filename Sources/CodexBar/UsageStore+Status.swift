import Foundation

extension UsageStore {
    /// Parses ISO8601 timestamps from third-party status JSON. Uses layered strategies so a single odd
    /// string (or ICU quirks on newer macOS builds) does not take down decoding.
    private nonisolated static func parseISO8601StatusDate(from raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        if let date = df.date(from: raw) { return date }
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        if let date = df.date(from: raw) { return date }
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        if let date = df.date(from: raw) { return date }
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return df.date(from: raw)
    }

    static func fetchStatus(from baseURL: URL) async throws -> ProviderStatus {
        let apiURL = baseURL.appendingPathComponent("api/v2/status.json")
        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 10

        let (data, _) = try await URLSession.shared.data(for: request, delegate: nil)

        struct Response: Decodable {
            struct Status: Decodable {
                let indicator: String
                let description: String?
            }

            struct Page: Decodable {
                let updatedAt: Date?

                private enum CodingKeys: String, CodingKey {
                    case updatedAt = "updated_at"
                }
            }

            let page: Page?
            let status: Status
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = Self.parseISO8601StatusDate(from: raw) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date")
            }
            return date
        }

        let response = try decoder.decode(Response.self, from: data)
        let indicator = ProviderStatusIndicator(rawValue: response.status.indicator) ?? .unknown
        return ProviderStatus(
            indicator: indicator,
            description: response.status.description,
            updatedAt: response.page?.updatedAt)
    }

    static func fetchWorkspaceStatus(productID: String) async throws -> ProviderStatus {
        guard let url = URL(string: "https://www.google.com/appsstatus/dashboard/incidents.json") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, _) = try await URLSession.shared.data(for: request, delegate: nil)
        return try Self.parseGoogleWorkspaceStatus(data: data, productID: productID)
    }

    static func parseGoogleWorkspaceStatus(data: Data, productID: String) throws -> ProviderStatus {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = Self.parseISO8601StatusDate(from: raw) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date")
            }
            return date
        }

        let incidents = try decoder.decode([GoogleWorkspaceIncident].self, from: data)
        let active = incidents.filter { $0.isRelevant(productID: productID) && $0.isActive }
        guard !active.isEmpty else {
            return ProviderStatus(indicator: .none, description: nil, updatedAt: nil)
        }

        var best: (
            indicator: ProviderStatusIndicator,
            incident: GoogleWorkspaceIncident,
            update: GoogleWorkspaceUpdate?)
        best = (indicator: .none, incident: active[0], update: active[0].mostRecentUpdate ?? active[0].updates?.last)

        for incident in active {
            let update = incident.mostRecentUpdate ?? incident.updates?.last
            let indicator = Self.workspaceIndicator(
                status: update?.status ?? incident.statusImpact,
                severity: incident.severity)
            if Self.indicatorRank(indicator) <= Self.indicatorRank(best.indicator) { continue }
            best = (indicator: indicator, incident: incident, update: update)
        }

        let description = Self.workspaceSummary(from: best.update?.text ?? best.incident.externalDesc)
        let updatedAt = best.update?.when ?? best.incident.modified ?? best.incident.begin
        return ProviderStatus(indicator: best.indicator, description: description, updatedAt: updatedAt)
    }

    private static func indicatorRank(_ indicator: ProviderStatusIndicator) -> Int {
        switch indicator {
        case .none: 0
        case .maintenance: 1
        case .minor: 2
        case .major: 3
        case .critical: 4
        case .unknown: 1
        }
    }

    private static func workspaceIndicator(status: String?, severity: String?) -> ProviderStatusIndicator {
        switch status?.uppercased() {
        case "AVAILABLE": return .none
        case "SERVICE_INFORMATION": return .minor
        case "SERVICE_DISRUPTION": return .major
        case "SERVICE_OUTAGE": return .critical
        case "SERVICE_MAINTENANCE", "SCHEDULED_MAINTENANCE": return .maintenance
        default: break
        }

        switch severity?.lowercased() {
        case "low": return .minor
        case "medium": return .major
        case "high": return .critical
        default: return .minor
        }
    }

    private static func workspaceSummary(from text: String?) -> String? {
        guard let text else { return nil }
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: true)
        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let lower = trimmed.lowercased()
            if lower.hasPrefix("**summary") || lower.hasPrefix("**description") || lower == "summary" {
                continue
            }
            var cleaned = trimmed.replacingOccurrences(of: "**", with: "")
            cleaned = cleaned.replacingOccurrences(
                of: #"\[([^\]]+)\]\([^)]+\)"#,
                with: "$1",
                options: .regularExpression)
            if cleaned.hasPrefix("- ") {
                cleaned.removeFirst(2)
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { return cleaned }
        }
        return nil
    }

    private struct GoogleWorkspaceIncident: Decodable {
        let begin: Date?
        let end: Date?
        let modified: Date?
        let externalDesc: String?
        let statusImpact: String?
        let severity: String?
        let affectedProducts: [GoogleWorkspaceProduct]?
        let currentlyAffectedProducts: [GoogleWorkspaceProduct]?
        let mostRecentUpdate: GoogleWorkspaceUpdate?
        let updates: [GoogleWorkspaceUpdate]?

        var isActive: Bool {
            self.end == nil
        }

        func isRelevant(productID: String) -> Bool {
            if let current = currentlyAffectedProducts {
                return current.contains(where: { $0.id == productID })
            }
            return self.affectedProducts?.contains(where: { $0.id == productID }) ?? false
        }
    }

    private struct GoogleWorkspaceProduct: Decodable {
        let title: String?
        let id: String
    }

    private struct GoogleWorkspaceUpdate: Decodable {
        let when: Date?
        let status: String?
        let text: String?
    }
}
