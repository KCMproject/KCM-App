import Foundation

protocol PortalSessionManaging {
    func fetchAnnouncements() -> [Announcement]
    func fetchCourses() -> [Course]
}
