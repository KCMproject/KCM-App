import XCTest
@testable import KCM_App

final class CampusSquareParserTests: XCTestCase {

    func testParseWeeklyTimetableFromRSW() throws {
        // 実際のHTML構造（ご提示いただいた内容の一部）
        let html = """
        <table class="rishu-koma" id="auto-table-3-2">
            <tbody>
                <tr>
                    <td>時限</td>
                    <td>月曜日</td>
                    <td>火曜日</td>
                    <td>水曜日</td>
                    <td>木曜日</td>
                    <td>金曜日</td>
                    <td>土曜日</td>
                </tr>
                <tr>
                    <td>1限</td>
                    <td>
                        <table class="rishu-koma-inner">
                            <tr>
                                <td>
                                    9091100001<br>
                                    道徳指導論<br>
                                    小野　方資<br>
                                    2.0単位<br>
                                    5-121
                                </td>
                            </tr>
                        </table>
                    </td>
                    <td>未登録</td>
                    <td>未登録</td>
                    <td>未登録</td>
                    <td>未登録</td>
                    <td>未登録</td>
                </tr>
                <tr>
                    <td>2限</td>
                    <td>未登録</td>
                    <td>未登録</td>
                    <td>未登録</td>
                    <td>未登録</td>
                    <td>未登録</td>
                    <td>未登録</td>
                </tr>
                <tr>
                    <td>3限</td>
                    <td>未登録</td>
                    <td>未登録</td>
                    <td>
                        <table class="rishu-koma-inner">
                            <tr>
                                <td>
                                    4024110070<br>
                                    ♪作曲Ⅲ<br>
                                    清水　祥平<br>
                                    2.0単位<br>
                                    N-301
                                </td>
                            </tr>
                        </table>
                    </td>
                    <td>未登録</td>
                    <td>未登録</td>
                    <td>未登録</td>
                </tr>
            </tbody>
        </table>
        """

        let results = CampusSquareParser.parseWeeklyTimetableFromRSW(from: html)

        // 検証
        XCTAssertEqual(results.count, 2, "2つの科目が抽出されるはずです")

        // 1限 月曜: 道徳指導論
        let doutoku = results.first { $0.title == "道徳指導論" }
        XCTAssertNotNil(doutoku)
        XCTAssertEqual(doutoku?.weekday, "月曜日")
        XCTAssertEqual(doutoku?.period, "1限")
        XCTAssertEqual(doutoku?.room, "5-121")

        // 3限 水曜: ♪作曲Ⅲ
        let sakkyoku = results.first { $0.title == "♪作曲Ⅲ" }
        XCTAssertNotNil(sakkyoku)
        XCTAssertEqual(sakkyoku?.weekday, "水曜日")
        XCTAssertEqual(sakkyoku?.period, "3限")
        XCTAssertEqual(sakkyoku?.room, "N-301")
    }

    func testParseWeeklyTimetableWithSaturday() throws {
        // 土曜日の授業を含むHTML
        let html = """
        <table class="rishu-koma">
            <tbody>
                <tr>
                    <td>時限</td><td>月</td><td>火</td><td>水</td><td>木</td><td>金</td><td>土曜日</td>
                </tr>
                <tr>
                    <td>2限</td>
                    <td>未登録</td><td>未登録</td><td>未登録</td><td>未登録</td><td>未登録</td>
                    <td>
                        <table class="rishu-koma-inner">
                            <tr>
                                <td>
                                    SAT001<br>
                                    土曜の特別講義<br>
                                    テスト講師<br>
                                    1.0単位<br>
                                    ホールA
                                </td>
                            </tr>
                        </table>
                    </td>
                </tr>
            </tbody>
        </table>
        """

        let results = CampusSquareParser.parseWeeklyTimetableFromRSW(from: html)

        let saturdayClass = results.first { $0.title == "土曜の特別講義" }
        XCTAssertNotNil(saturdayClass)
        XCTAssertEqual(saturdayClass?.weekday, "土曜日")
        XCTAssertEqual(saturdayClass?.period, "2限")
        XCTAssertEqual(saturdayClass?.room, "ホールA")
    }

    func testParseSchedule() throws {
        // 既存の parseSchedule (今日の予定) のテスト
        let html = """
        <td class="day">
            <span class="kaiko">1限:道徳指導論@5-121</span>
        </td>
        """
        
        let results = CampusSquareParser.parseSchedule(from: html)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "道徳指導論")
        XCTAssertEqual(results[0].period, "1")
        XCTAssertEqual(results[0].room, "5-121")
    }
}
