import Testing
@testable import nimotch

@Suite("Meeting link detection")
struct LinkDetectorTests {
    @Test("Recognises meeting links in typical Outlook/Teams/Zoom/Webex/Meet text", arguments: [
        ("Join on your computer\n<https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=x>", MeetingLink.Service.teams),
        ("Join: https://teams.microsoft.com/meet/3812345678?p=abcdef", .teams),
        ("https://nam12.safelinks.protection.outlook.com/?url=https%3A%2F%2Fzoom.us%2Fj%2F123456789%3Fpwd%3Dabc&data=x", .zoom),
        ("Webex: https://acme.webex.com/acme/j.php?MTID=m123", .webex),
        ("https://acme.webex.com/meet/nimai", .webex),
        ("Room 4.12, https://meet.google.com/abc-defg-hij", .meet),
    ])
    func detects(text: String, service: MeetingLink.Service) {
        #expect(LinkDetector.find(in: [nil, text])?.service == service)
    }

    @Test func ignoresNonMeetingLinks() {
        #expect(LinkDetector.find(in: ["Agenda https://www.notion.so/page and https://teams.microsoft.com/"]) == nil)
        #expect(LinkDetector.find(in: [nil, "", "no links here"]) == nil)
    }

    @Test func checksFieldsInOrder() {
        let link = LinkDetector.find(in: ["https://zoom.us/j/1", "https://meet.google.com/abc-defg-hij"])
        #expect(link?.service == .zoom)
    }

    @Test func unwrapsSafeLinks() {
        let link = LinkDetector.find(in: ["https://eur01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fmeet.google.com%2Fabc-defg-hij&data=1"])
        #expect(link?.url.absoluteString == "https://meet.google.com/abc-defg-hij")
    }
}
