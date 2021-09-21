import XCTest
@testable import Txtar

final class ArchiveTests: XCTestCase {
	func testFormat() {
		struct TestCase {
			let desc: String
			let input: Archive
			let want: String
		}

		let testcases = [
			TestCase(desc: "basic",
					 input: Archive(comment: "comment1\ncomment2\n".data(using: .utf8)!,
									files: [
										File(name: "file1", data: "File 1 text.\n-- foo ---\nMore file 1 text.\n".data(using: .utf8)!),
										File(name: "file 2", data: "File 2 text.\n".data(using: .utf8)!),
										File(name: "empty", data: "".data(using: .utf8)!),
										File(name: "empty filename line", data: "some content\n-- --\n".data(using: .utf8)!),
										File(name: "noNL", data: "hello world".data(using: .utf8)!),
									]),
					 want: """
comment1
comment2
-- file1 --
File 1 text.
-- foo ---
More file 1 text.
-- file 2 --
File 2 text.
-- empty --
-- empty filename line --
some content
-- --
-- noNL --
hello world

""")
		]

		for tc in testcases {
			let got = String(data: tc.input.format(), encoding: .utf8)
			XCTAssertEqual(got, tc.want, tc.desc)
		}
	}

	func TestParse() {
		struct TestCase {
			let desc: String
			let input: Data
			let want: Archive
		}

		let testcases = [
			TestCase(desc: "basic",
					 input: """
comment1
comment2
-- file1 --
File 1 text.
-- foo ---
More file 1 text.
-- file 2 --
File 2 text.
-- empty --
-- noNL --
hello world
-- empty filename line --
some content
-- --
""".data(using: .utf8)!,
					 want: Archive(comment: "".data(using: .utf8)!,
								   files: [
									File(name: "file1", data: "File 1 text.\n-- foo ---\nMore file 1 text.\n".data(using: .utf8)!),
									File(name: "file 2", data: "File 2 text.\n".data(using: .utf8)!),
									File(name: "empty", data: "".data(using: .utf8)!),
									File(name: "noNL", data: "hello world".data(using: .utf8)!),
									File(name: "empty filename line", data: "some content\n-- --\n".data(using: .utf8)!),
								   ])),
		]

		for tc in testcases {
			let got = Archive.parse(tc.input)
			XCTAssertEqual(got, tc.want, tc.desc)
		}
	}
}

final class AppendWithNewlineTests: XCTestCase {
	func testAppendWithNewline() {
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
			var buf = Data()
			let input = tc.input.data(using: .utf8)!
			appendWithNewline(input, to: &buf)
			let want = tc.want.data(using: .utf8)
			XCTAssertEqual(buf, want, String(format: "input \(tc.input)"))
		}
	}
}

final class IsMarkerLineTests: XCTestCase {
	func testIsMarkerLine() throws {
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
			TestCase(desc: "wrong end marker", input: "-- file name -\n".data(using: .utf8)!),
			TestCase(desc: "white space is shared", input: "-- --\n".data(using: .utf8)!),
			TestCase(desc: "bad filename encoding", input: Data([0x2d, 0x2d, 0x20, 0xc0 /* bad */, 0x20, 0x2d, 0x2d, 0x0a])),
			
			// happy path
			TestCase(desc: "basic",
					 input: "-- file name --\n".data(using: .utf8)!,
					 want: ("file name", "".data(using: .utf8)!)),
			TestCase(desc: "no end newline",
					 input: "-- file name --".data(using: .utf8)!,
					 want: ("file name", "".data(using: .utf8)!)),
			TestCase(desc: "whitespace around filename",
					 input: "--  \t file name\t --\n".data(using: .utf8)!,
					 want: ("file name", "".data(using: .utf8)!)),
			TestCase(desc: "empty filename",
					 input: "--  --\n".data(using: .utf8)!,
					 want: ("", "".data(using: .utf8)!)),
			TestCase(desc: "after",
					 input: "-- file name --\nremaining".data(using: .utf8)!,
					 want: ("file name", "remaining".data(using: .utf8)!)),
		]
		
		for tc in testcases {
			let got = isMarkerLine(Slice(tc.input))
			if tc.want == nil {
				XCTAssertNil(got, tc.desc)
			} else {
				let got = try XCTUnwrap(got, tc.desc)
				XCTAssertEqual(got.name, tc.want!.name, tc.desc)
				XCTAssertEqual(Data(got.after), tc.want!.after, tc.desc)
			}
		}
	}
}

final class FindNextFileMarkerTests: XCTestCase {
	func testFindNextFileMarker() throws {
		struct TestCase {
			let desc: String
			let input: Data
			let want: (before: Data, name: String, after: Data)?

			init(desc: String, input: Data, want: (before: Data, name: String, after: Data)? = nil) {
				self.desc = desc
				self.input = input
				self.want = want
			}
		}

		let testcases = [
			TestCase(desc: "normal",
					 input: "some text\n\n-- file name --\ndata\n".data(using: .utf8)!,
					 want: (before: "some text\n\n".data(using: .utf8)!, name: "file name", after: "data\n".data(using: .utf8)!)),
			TestCase(desc: "empty after",
					 input: "some text\n\n-- file name --\n".data(using: .utf8)!,
					 want: (before: "some text\n\n".data(using: .utf8)!, name: "file name", after: "".data(using: .utf8)!)),
			TestCase(desc: "no file marker",
					 input: "some text".data(using: .utf8)!,
					 want: nil),
			TestCase(desc: "no file marker (newlines)",
					 input: "some text\nmore".data(using: .utf8)!,
					 want: nil),
			TestCase(desc: "no file marker (ending in newline)",
					 input: "some text\nmore\n".data(using: .utf8)!,
					 want: nil),
			TestCase(desc: "empty before",
					 input: "-- file name --\n".data(using: .utf8)!,
					 want: (before: "".data(using: .utf8)!, name: "file name", after: "".data(using: .utf8)!)),
		]

		for tc in testcases {
			let got = findNextFileMarker(Slice(tc.input))
			if tc.want == nil {
				XCTAssertNil(got, tc.desc)
			} else {
				let got = try XCTUnwrap(got, tc.desc)
				XCTAssertEqual(String(data: Data(got.before), encoding: .utf8), String(data: tc.want!.before, encoding: .utf8), tc.desc)
				XCTAssertEqual(got.name, tc.want!.name, tc.desc)
				XCTAssertEqual(Data(got.after), tc.want!.after, tc.desc)
			}
		}
	}
}
