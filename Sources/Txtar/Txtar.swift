import Foundation

/*
 Txtar is a trivial text-based file archive format.

 The goals for the format are:
   - be trivial enough to create and edit by hand.
   - be able to store trees of text files describing go command test cases.
   - diff nicely in git history and code reviews.

 Non-goals include being a completely general archive format,
 storing binary data, storing file modes, storing special files like
 symbolic links, and so on.

 A txtar archive is zero or more comment lines and then a sequence of file entries.
 Each file entry begins with a file marker line of the form "-- FILENAME --"
 and is followed by zero or more file content lines making up the file data.
 The comment or file content ends at the next file marker line.
 The file marker line must begin with the three-byte sequence "-- "
 and end with the three-byte sequence " --", but the enclosed
 file name can be surrounding by additional white space,
 all of which is stripped.
 
 The file name and marker sequences are UTF-8 encoded.
 
 If the txtar file is missing a trailing newline on the final line,
 parsers should consider a final newline to be present anyway.
 
 There are no possible syntax errors in a txtar archive.
 
 (This description was copied from the Go x/tools repository.)
*/

/// A collection of files.
public struct Archive: Equatable {
	let comment: Data
	let files: [File]

	/// Parse the serialized form of an archive.
	public static func parse(_ data: Data) -> Archive {
		var remainingData: Slice<Data> = data[data.startIndex..<data.endIndex]

		guard let next = findNextFileMarker(remainingData) else {
			// only comment is present.
			return Archive(comment: withNewline(data), files: [])
		}

		let comment = Data(next.before)
		var files = [File]()

		var name = next.name
		remainingData = next.after

		while true {
			guard let next = findNextFileMarker(remainingData) else {
				files.append(File(name: name, data: withNewline(Data(remainingData))))
				break
			}
			files.append(File(name: name, data: Data(next.before)))
			name = next.name
			remainingData = next.after
		}

		return Archive(comment: comment, files: files)
	}

	/// Returns the txtar representation of this archive.
	/// It is assumed that this archive's files and comment are well-formed.
	/// Particularly, the comment and the file data contain no file marker lines,
	/// and all file names are non-empty.
	public func format() -> Data {
		var out = Data()
		out.append(formatComment(comment))
		for file in files {
			out.append(formatFile(file))
		}
		return out
	}
}

/// A single file in an Archive.
public struct File: Equatable {
	var name: String
	var data: Data
}

internal func formatFile(_ file: File) -> Data {
	var out = Data()
	out.append(markerStart)
	out.append(file.name.data(using: .utf8)!)
	out.append(markerEnd)
	out.append(newline)
	appendWithNewline(file.data, to: &out)
	return out
}

internal func formatComment(_ comment: Data?) -> Data {
	var out = Data()
	if let c = comment {
		appendWithNewline(c, to: &out)
	}
	return out
}

let newlineByte: UInt8 = 0x0a
let markerStart = "-- ".data(using: .utf8)!
let markerEnd = " --".data(using: .utf8)!
let newline = "\n".data(using: .utf8)!

// Like withNewline but accepts a buffer to modify instead of returning
// a new buffer.
internal func appendWithNewline(_ data: Data, to: inout Data) {
	if data.isEmpty || data.last! == newlineByte {
		to.append(data)
		return
	}
	to.append(data)
	to.append(newline)
}

// If the given data is empty or ends in \n, returns a copy of data as is.
// Otherwise returns a copy of data with a newline appended after.
internal func withNewline(_ data: Data) -> Data {
	if data.isEmpty || data.last! == newlineByte {
		return Data(data)
	}
	var out = Data(data)
	out.append(newline)
	return out
}

internal func findNextFileMarker(_ data: Slice<Data>) -> (before: Slice<Data>, name: String, after: Slice<Data>)? {
	var idx = data.startIndex
	while true {
		if let markerLine = isMarkerLine(data[idx...]) {
			return (before: data[..<idx], name: markerLine.name, after: markerLine.after)
		}
		if let newlineIdx = data[idx...].firstIndex(of: newlineByte) {
			// try at next line
			idx = newlineIdx + 1
			continue
		}
		return nil
	}
}

// Checks whether data begins with a file marker line. If so,
// returns the filename and remaining data after the file marker line.
// Otherwise, returns nil.
internal func isMarkerLine(_ data: Slice<Data>) -> (name: String, after: Slice<Data>)? {
	guard data.starts(with: markerStart) else {
		return nil
	}

	let line: Slice<Data>
	let remaining: Slice<Data>
	if let lineEndIdx = data.firstIndex(of: newlineByte) {
		line = data[..<lineEndIdx]
		remaining = data[lineEndIdx+1..<data.endIndex]
	} else {
		line = data
		remaining = data[data.endIndex...]
	}
	
	guard endsWithMarkerEnd(line) else {
		return nil
	}
	
	// Ensure the white space at the end of the start marker and the
	// end marker doesn't overlap.
	guard line.count >= markerStart.count + markerEnd.count else {
		return nil
	}
	
	// Extract the filename.
	let name = line[line.startIndex+markerStart.count..<line.endIndex-markerEnd.count]
	// TODO(nishanth): possible to construct String from Slice<Data>?
	guard let name = String(data: Data(name), encoding: .utf8)?
			.trimmingCharacters(in: CharacterSet.whitespaces) else {
		return nil
	}
	
	return (name, remaining)
}

// Does the data end with the end marker?
internal func endsWithMarkerEnd(_ data: Slice<Data>) -> Bool {
	guard data.endIndex - markerEnd.count >= data.startIndex else {
		return false
	}
	// Example:
	// -- n --
	// 2345678; endIndex=9; markerEnd.count=3; 9-3=6; 6..<9
	let suffixRange = data.endIndex-markerEnd.count..<data.endIndex
	return data[suffixRange].elementsEqual(markerEnd)
}
