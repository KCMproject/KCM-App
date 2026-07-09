import SwiftUI
import UIKit

enum SyllabusSearchOpener {
    private static let syllabusURLString = "https://cs.kunitachi.ac.jp/campusweb/campussquare.do?_flowId=SBW3701300-flow&link=menu-link-mf-164899"

    static func openSearch(for title: String, setWebDestination: @escaping (CampusWebDestination) -> Void) {
        guard let url = URL(string: syllabusURLString) else { return }
        UIPasteboard.general.string = title
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            setWebDestination(CampusWebDestination(url: url, title: "シラバス参照", autoSearchText: title))
        }
    }
}
