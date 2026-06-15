import Foundation

/// 掲示板（お知らせ）の取得・詳細解決を担当するクライアント
final class PortalAnnouncementClient {

    private let networkClient: PortalNetworkClient
    private let authClient: PortalAuthClient
    private let formClient: PortalFormClient
    private let baseURL: String
    private let portalURL = "/portal.do"
    private let mainURL: String

    init(networkClient: PortalNetworkClient, authClient: PortalAuthClient, formClient: PortalFormClient) {
        self.networkClient = networkClient
        self.authClient = authClient
        self.formClient = formClient
        self.baseURL = networkClient.baseURL
        self.mainURL = "\(baseURL)\(portalURL)?page=main"
    }

    // MARK: - 公開API

    func fetchAnnouncements() async throws -> [NoticeCard] {
        try await authClient.executeWithAutoRelogin {
            try await self._fetchAnnouncements()
        }
    }

    func fetchNoticeAttachments(for notice: NoticeCard) async throws -> [NoticeAttachment] {
        try await authClient.executeWithAutoRelogin {
            try await self._fetchNoticeAttachments(for: notice)
        }
    }

    func resolveNoticeDetailURL(for notice: NoticeCard) async throws -> URL? {
        try await authClient.executeWithAutoRelogin {
            try await self._resolveNoticeDetailURL(for: notice)
        }
    }

    // MARK: - 内部実装

    private func _fetchAnnouncements() async throws -> [NoticeCard] {
        let mainHtml = try await networkClient.fetchHTML(from: mainURL)
        try PortalClientHelper.validatePortalPage(mainHtml)

        guard let bulletinPath = CampusSquareParser.extractHref(from: mainHtml, withId: "menu-link-mf-164854") else {
            throw CampusSquareLoginError.portalError("掲示板リンクが見つかりません")
        }

        let bulletinURL = PortalClientHelper.absolutePortalURLString(from: bulletinPath, baseURL: baseURL)
        let html = try await networkClient.fetchHTML(from: bulletinURL, referer: mainURL)
        try PortalClientHelper.validatePortalPage(html)

        let genreNotices = try await fetchAnnouncementGenreLists(from: html, referer: bulletinURL)
        if !genreNotices.isEmpty {
            return genreNotices
        }

        let directNotices = CampusSquareParser.parseAnnouncements(from: html)
        if !directNotices.isEmpty {
            return directNotices
        }

        let searchNotices = try await fetchAnnouncementSearchResults(from: html, referer: bulletinURL)
        if !searchNotices.isEmpty {
            return searchNotices
        }

        throw CampusSquareLoginError.portalError("掲示板を読み込めませんでした")
    }

    private func _fetchNoticeAttachments(for notice: NoticeCard) async throws -> [NoticeAttachment] {
        guard let path = notice.url, !path.isEmpty else {
            return []
        }

        let detailURL = PortalClientHelper.absolutePortalURLString(from: path, baseURL: baseURL)
        let html = try await networkClient.fetchHTML(from: detailURL, referer: mainURL)
        if isNoticeDetailPage(html, for: notice) {
            return CampusSquareParser.parseNoticeAttachments(from: html, baseURL: baseURL)
        }

        if let freshDetail = try await resolveFreshNoticeDetailURL(for: notice, mainURL: mainURL) {
            let freshHtml = try await networkClient.fetchHTML(from: freshDetail.url, referer: freshDetail.referer)
            guard isNoticeDetailPage(freshHtml, for: notice) else {
                throw CampusSquareLoginError.portalError("掲示板詳細を取得できませんでした")
            }
            return CampusSquareParser.parseNoticeAttachments(from: freshHtml, baseURL: baseURL)
        }

        throw CampusSquareLoginError.portalError("掲示板詳細URLを更新できませんでした")
    }

    private func _resolveNoticeDetailURL(for notice: NoticeCard) async throws -> URL? {
        guard let freshDetail = try await resolveFreshNoticeDetailURL(for: notice, mainURL: mainURL) else {
            return nil
        }
        return URL(string: freshDetail.url)
    }

    // MARK: - ページング・ジャンル・検索

    private func collectAnnouncementsWithPagination(
        initialHtml: String,
        initialURL: String,
        referer: String,
        maxPages: Int = 10
    ) async throws -> (notices: [NoticeCard], lastHtml: String, lastURL: String) {
        var allByID: [String: NoticeCard] = [:]
        var currentHtml = initialHtml
        var currentURL = initialURL
        var pageCount = 0

        while pageCount < maxPages {
            let notices = CampusSquareParser.parseAnnouncements(from: currentHtml)
            for n in notices { allByID[n.id] = n }

            guard let nextHref = PortalClientHelper.extractNextPageHref(from: currentHtml) else {
                break
            }
            pageCount += 1

            let nextURL = PortalClientHelper.absolutePortalURLString(from: nextHref, baseURL: baseURL)
            let nextHtml = try await networkClient.fetchHTML(from: nextURL, referer: currentURL)
            try PortalClientHelper.validatePortalPage(nextHtml)

            currentHtml = nextHtml
            currentURL = nextURL
        }

        return (PortalClientHelper.sortAnnouncements(Array(allByID.values)), currentHtml, currentURL)
    }

    private func fetchAnnouncementGenreLists(from topHtml: String, referer: String) async throws -> [NoticeCard] {
        let targets = CampusSquareParser.extractNoticeGenreLinks(from: topHtml)
        guard !targets.isEmpty else {
            return []
        }

        var currentHtml = topHtml
        var currentReferer = referer
        var noticesByID: [String: NoticeCard] = [:]

        for target in targets {
            let currentTargets = CampusSquareParser.extractNoticeGenreLinks(from: currentHtml)
            let link = currentTargets.first {
                $0.keijitype == target.keijitype && $0.genrecd == target.genrecd
            } ?? target
            let url = PortalClientHelper.absolutePortalURLString(from: link.href, baseURL: baseURL)

            do {
                let html = try await networkClient.fetchHTML(from: url, referer: currentReferer)
                try PortalClientHelper.validatePortalPage(html)
                let collected = try await collectAnnouncementsWithPagination(
                    initialHtml: html,
                    initialURL: url,
                    referer: currentReferer,
                    maxPages: 10
                )
                for notice in collected.notices {
                    noticesByID[notice.id] = notice
                }
                currentHtml = collected.lastHtml
                currentReferer = collected.lastURL
            } catch {
                continue
            }
        }

        return PortalClientHelper.sortAnnouncements(Array(noticesByID.values))
    }

    private func resolveFreshNoticeDetailURL(
        for notice: NoticeCard,
        mainURL: String
    ) async throws -> (url: String, referer: String)? {
        guard let values = noticeQueryValues(from: notice.url),
              let keijitype = values["keijitype"],
              let genrecd = values["genrecd"],
              let seqNo = values["seqNo"] else {
            return nil
        }

        let mainHtml = try await networkClient.fetchHTML(from: mainURL)
        try PortalClientHelper.validatePortalPage(mainHtml)
        guard let bulletinPath = CampusSquareParser.extractHref(from: mainHtml, withId: "menu-link-mf-164854") else {
            return nil
        }

        let bulletinURL = PortalClientHelper.absolutePortalURLString(from: bulletinPath, baseURL: baseURL)
        let topHtml = try await networkClient.fetchHTML(from: bulletinURL, referer: mainURL)
        try PortalClientHelper.validatePortalPage(topHtml)

        guard let genreLink = CampusSquareParser.extractNoticeGenreLinks(from: topHtml).first(where: {
            $0.keijitype == keijitype && $0.genrecd == genrecd
        }) else {
            return nil
        }

        let genreURL = PortalClientHelper.absolutePortalURLString(from: genreLink.href, baseURL: baseURL)
        let genreHtml = try await networkClient.fetchHTML(from: genreURL, referer: bulletinURL)
        try PortalClientHelper.validatePortalPage(genreHtml)

        guard let detailHref = extractNoticeDetailHref(from: genreHtml, keijitype: keijitype, genrecd: genrecd, seqNo: seqNo) else {
            return nil
        }

        let detailURL = PortalClientHelper.absolutePortalURLString(from: detailHref, baseURL: baseURL)
        return (detailURL, genreURL)
    }

    private func extractNoticeDetailHref(from html: String, keijitype: String, genrecd: String, seqNo: String) -> String? {
        let linkPattern = "<a[^>]*href\\s*=\\s*['\"]([^'\"]*seqNo=\(NSRegularExpression.escapedPattern(for: seqNo))[^'\"]*)['\"][^>]*>"
        guard let regex = try? NSRegularExpression(pattern: linkPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }

        for match in regex.matches(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)) {
            guard let range = Range(match.range(at: 1), in: html) else { continue }
            let href = String(html[range]).replacingOccurrences(of: "&amp;", with: "&")
            guard let values = noticeQueryValues(from: href),
                  values["keijitype"] == keijitype,
                  values["genrecd"] == genrecd,
                  values["seqNo"] == seqNo else {
                continue
            }
            return href
        }

        return nil
    }

    private func noticeQueryValues(from rawURL: String?) -> [String: String]? {
        guard let rawURL, !rawURL.isEmpty else { return nil }
        let decodedURL = rawURL.replacingOccurrences(of: "&amp;", with: "&")
        let absoluteURL: String
        if decodedURL.hasPrefix("http://") || decodedURL.hasPrefix("https://") {
            absoluteURL = decodedURL
        } else if decodedURL.hasPrefix("/") {
            absoluteURL = "https://cs.kunitachi.ac.jp\(decodedURL)"
        } else {
            absoluteURL = "\(baseURL)/\(decodedURL)"
        }

        guard let components = URLComponents(string: absoluteURL),
              let queryItems = components.queryItems else {
            return nil
        }

        var values: [String: String] = [:]
        for item in queryItems {
            values[item.name] = item.value ?? ""
        }
        return values
    }

    private func isNoticeDetailPage(_ html: String, for notice: NoticeCard) -> Bool {
        html.contains("KeijiReferView")
            && (html.contains("keiji-title") || html.contains("keiji-naiyo"))
            && html.contains(notice.title)
    }

    private func fetchAnnouncementSearchResults(from searchHtml: String, referer: String) async throws -> [NoticeCard] {
        guard let initialSearchHtml = try await fetchAnnouncementSearchPage(from: searchHtml, referer: referer) else {
            return []
        }

        let genreValues = CampusSquareParser.parseSelectValues(from: initialSearchHtml, formID: "keijiSearchForm", selectName: "genreCd")
        var noticesByID: [String: NoticeCard] = [:]
        let searchTargets = genreValues.isEmpty ? [""] : genreValues

        for (index, genreValue) in searchTargets.enumerated() {
            let formHtml: String
            if index == 0 {
                formHtml = initialSearchHtml
            } else {
                let freshTopHtml = try await networkClient.fetchHTML(from: referer, referer: referer)
                try PortalClientHelper.validatePortalPage(freshTopHtml)
                guard let freshSearchHtml = try await fetchAnnouncementSearchPage(from: freshTopHtml, referer: referer) else {
                    continue
                }
                formHtml = freshSearchHtml
            }

            let baseFields = CampusSquareParser.parseFormFields(from: formHtml, formID: "keijiSearchForm")
            guard !baseFields.isEmpty else {
                continue
            }

            let html = try await submitAnnouncementSearch(fields: baseFields, genreValue: genreValue, referer: referer)
            try PortalClientHelper.validatePortalPage(html)
            let tempURL = referer
            let collected = try await collectAnnouncementsWithPagination(
                initialHtml: html,
                initialURL: tempURL,
                referer: referer,
                maxPages: 10
            )
            for notice in collected.notices {
                noticesByID[notice.id] = notice
            }
        }

        return PortalClientHelper.sortAnnouncements(Array(noticesByID.values))
    }

    private func fetchAnnouncementSearchPage(from topHtml: String, referer: String) async throws -> String? {
        if !CampusSquareParser.parseFormFields(from: topHtml, formID: "keijiSearchForm").isEmpty {
            return topHtml
        }

        let topFields = CampusSquareParser.parseFormFields(from: topHtml, formID: "keijiReferForm")
        guard !topFields.isEmpty else { return nil }

        let html = try await formClient.submitPortalForm(
            fields: topFields + [("_eventId_search", "掲示情報検索")],
            referer: referer
        )
        try PortalClientHelper.validatePortalPage(html)
        return html
    }

    private func submitAnnouncementSearch(fields: [(String, String)], genreValue: String, referer: String) async throws -> String {
        let bodyFields = fields.map { field in
            field.0 == "genreCd" && !genreValue.isEmpty ? (field.0, genreValue) : field
        }
        return try await formClient.submitPortalForm(fields: bodyFields, referer: referer)
    }
}
