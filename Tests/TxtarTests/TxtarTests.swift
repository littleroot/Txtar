import XCTest
@testable import Txtar

final class WithFixedNewlineTests: XCTestCase {
    func testWithFixedNewline() {
        struct TestCase {
            let input, want: String
        }
        
        let testcases = [
            TestCase(input: "", want: ""),
            TestCase(input: "\n", want: "\n"),
            TestCase(input: "\r\n", want: "\r\n"),
            TestCase(input: "hello", want: "hello\n"),
            TestCase(input: "hello\n", want: "hello\n"),
        ]
        
        for tc in testcases {
            let input = tc.input.data(using: .utf8)!
            let got = withFixedNewline(input)
            let want = tc.want.data(using: .utf8)
            XCTAssertEqual(got, want, String(format: "input \(tc.input)"))
        }
    }
}

final class StartsWithMarkerLineTests: XCTestCase {
	func testStartsWithMarkerLine() throws {
		struct TestCase {
			let desc: String
			let input: Data
			let want: (name: String, after: Data)?
			
			init(desc: String, input: Data, want: (name: String, after: Data)? = nil) {
				self.desc = desc
				self.input = input
				self.want = want
			}
		}
		
		let testcases = [
			// sad path
			TestCase(desc: "wrong start marker", input: "what".data(using: .utf8)!),
			TestCase(desc: "no end newline", input: "-- filename --".data(using: .utf8)!),
			TestCase(desc: "wrong end marker", input: "-- filename -\n".data(using: .utf8)!),
			TestCase(desc: "white space is shared", input: "-- --\n".data(using: .utf8)!),
			TestCase(desc: "bad filename encoding", input: Data([0x2d, 0x2d, 0x20, 0xc0 /* bad */, 0x20, 0x2d, 0x2d, 0x0a])),
			// happy path
			TestCase(desc: "basic", input: "-- filename --\n".data(using: .utf8)!, want: ("filename", "".data(using: .utf8)!)),
			TestCase(desc: "whitespace around filename",
					 input: "--  \t filename\t --\n".data(using: .utf8)!,
					 want: ("filename", "".data(using: .utf8)!)),
			TestCase(desc: "empty filename", input: "--  --\n".data(using: .utf8)!, want: ("", "".data(using: .utf8)!)),
			TestCase(desc: "after", input: "-- filename --\nremaining".data(using: .utf8)!, want: ("filename", "remaining".data(using: .utf8)!)),
		]
		
		for tc in testcases {
			let got = startsWithMarkerLine(Slice(tc.input))
			if tc.want == nil {
				XCTAssertNil(got, tc.desc)
			} else {
				let got = try XCTUnwrap(got)
				XCTAssertEqual(got.name, tc.want!.name, tc.desc)
				XCTAssertEqual(Data(got.after), tc.want!.after, tc.desc)
			}
		}
	}
}
