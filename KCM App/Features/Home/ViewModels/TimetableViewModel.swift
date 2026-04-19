import Foundation
import Combine

@MainActor
final class TimetableViewModel: ObservableObject {
    static let shared = TimetableViewModel(portalClient: PortalClientFactory.makeLoginService())
    
    @Published var courses: [Course] = []
    @Published var weeklySchedule: [[ClassCell]] = Array(repeating: Array(repeating: .empty, count: 5), count: 6)
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let portalClient: PortalClientProtocol
    private let cacheStore = PortalCacheStore.shared

    init(portalClient: PortalClientProtocol) {
        self.portalClient = portalClient
    }

    func loadCachedData() {
        let cachedCourses = cacheStore.loadCourses()
        guard !cachedCourses.isEmpty else { return }
        applyCourses(cachedCourses)
    }

    func initialFetch() async {
        _ = await refreshFromServer()
    }

    func refreshFromServer() async -> Bool {
        isLoading = true
        errorMessage = nil

        do {
            let fetchedCourses = try await portalClient.fetchTimetable()
            let didUpdate = fetchedCourses != courses

            applyCourses(fetchedCourses)
            cacheStore.saveCourses(fetchedCourses)
            isLoading = false
            return didUpdate
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
            return false
        }
    }

    private func applyCourses(_ fetchedCourses: [Course]) {
        var grid = Array(repeating: Array(repeating: ClassCell.empty, count: 5), count: 6)
        let weekdayMap = ["月": 0, "火": 1, "水": 2, "木": 3, "金": 4]

        for course in fetchedCourses {
            guard let dayIdx = weekdayMap[course.weekday] else { continue }
            let periods = course.period.split(separator: ",").compactMap { Int($0) }

            for periodInt in periods where (1...6).contains(periodInt) {
                grid[periodInt - 1][dayIdx] = .filled(course.title, course.room)
            }
        }

        courses = fetchedCourses
        weeklySchedule = grid
    }
}
