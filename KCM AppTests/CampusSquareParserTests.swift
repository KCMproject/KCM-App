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
                                    N-301<br>
                                    14:00～14:23
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
        XCTAssertNil(doutoku?.startTime)
        XCTAssertNil(doutoku?.dateString)

        // 3限 水曜: ♪作曲Ⅲ
        let sakkyoku = results.first { $0.title == "♪作曲Ⅲ" }
        XCTAssertNotNil(sakkyoku)
        XCTAssertEqual(sakkyoku?.weekday, "水曜日")
        XCTAssertEqual(sakkyoku?.period, "3限")
        XCTAssertEqual(sakkyoku?.room, "N-301")
        XCTAssertEqual(sakkyoku?.startTime, "14:00")
        XCTAssertEqual(sakkyoku?.endTime, "14:23")
        XCTAssertNil(sakkyoku?.dateString)
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
            <script>addSchedule(20260413);</script>
        </td>
        """
        
        let results = CampusSquareParser.parseSchedule(from: html)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "道徳指導論")
        XCTAssertEqual(results[0].period, "1")
        XCTAssertEqual(results[0].room, "5-121")
        XCTAssertNil(results[0].startTime)
        XCTAssertEqual(results[0].dateString, "2026-04-13")
    }

    func testParseScheduleWithTime() throws {
        // 時間が含まれるスケジュール
        let html = """
        <td class="day">
            <span class="kaiko">3限(14:00〜14:23):♪作曲Ⅲ@N-301</span>
            <script>addSchedule(20260415);</script>
        </td>
        """
        
        let results = CampusSquareParser.parseSchedule(from: html)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "♪作曲Ⅲ")
        XCTAssertEqual(results[0].period, "3")
        XCTAssertEqual(results[0].startTime, "14:00")
        XCTAssertEqual(results[0].endTime, "14:23")
        XCTAssertEqual(results[0].room, "N-301")
        XCTAssertEqual(results[0].dateString, "2026-04-15")
    }

    func testParseAnnouncementsFromNoticeTable() throws {
        let html = """
        <table>
            <tr>
                <td>2026/04/27 13:35:02</td>
                <td>
                    <a href="campussquare.do?_flowExecutionKey=abc&amp;_eventId=displayMidoku&amp;keijitype=4&amp;genrecd=429&amp;seqNo=382">求人についてのお知らせ</a>
                </td>
                <td align="center">-</td>
                <td>全学掲示板</td>
                <td>学務部</td>
                <td>学生支援課</td>
                <td>2026/04/27 13:32から<br>2026/05/27 13:32まで</td>
            </tr>
        </table>
        """

        let results = CampusSquareParser.parseAnnouncements(from: html)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "求人についてのお知らせ")
        XCTAssertEqual(results[0].date, "2026/04/27")
        XCTAssertEqual(results[0].category, "全学掲示板")
        XCTAssertEqual(results[0].url, "campussquare.do?_flowExecutionKey=abc&_eventId=displayMidoku&keijitype=4&genrecd=429&seqNo=382")
    }

    func testExtractNoticeGenreLinks() throws {
        let html = """
        <a href="https://cs.kunitachi.ac.jp/campusweb/campussquare.do?_flowExecutionKey=abc&amp;_eventId=dispKeijiListGenre&amp;keijitype=4&amp;genrecd=429">全学掲示板</a>
        <a href="https://cs.kunitachi.ac.jp/campusweb/campussquare.do?_flowExecutionKey=abc&amp;_eventId=dispKeijiListGenre&amp;keijitype=3&amp;genrecd=431">個人掲示板</a>
        """

        let links = CampusSquareParser.extractNoticeGenreLinks(from: html)

        XCTAssertEqual(links.count, 2)
        XCTAssertEqual(links[0].keijitype, "4")
        XCTAssertEqual(links[0].genrecd, "429")
        XCTAssertTrue(links[0].href.contains("_eventId=dispKeijiListGenre"))
        XCTAssertEqual(links[1].keijitype, "3")
        XCTAssertEqual(links[1].genrecd, "431")
    }

    func testParseNoticeAttachments() throws {
        let html = """
        <table>
            <tbody>
                <tr><th class="keiji-normal">添付ファイル</th></tr>
                <tr>
                    <td class="keiji-normal">
                        <a href="campussquare.do?_flowExecutionKey=abc&amp;_eventId=download&amp;keijitype=4&amp;genrecd=429&amp;seqNo=329&amp;index=0">ミッシャ・マイスキー学内.pdf</a>
                    </td>
                </tr>
            </tbody>
        </table>
        """

        let attachments = CampusSquareParser.parseNoticeAttachments(from: html, baseURL: "https://cs.kunitachi.ac.jp/campusweb")

        XCTAssertEqual(attachments.count, 1)
        XCTAssertEqual(attachments[0].title, "ミッシャ・マイスキー学内.pdf")
        XCTAssertEqual(attachments[0].url, "https://cs.kunitachi.ac.jp/campusweb/campussquare.do?_flowExecutionKey=abc&_eventId=download&keijitype=4&genrecd=429&seqNo=329&index=0")
    }
}
