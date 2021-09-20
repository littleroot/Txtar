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
 
 The filename is UTF-8 encoded.
 
 If the txtar file is missing a trailing newline on the final line,
 parsers should consider a final newline to be present anyway.
 
 There are no possible syntax errors in a txtar archive.
 
 (This description was copied from the Go x/tools repository.)
*/

let newlineByte: UInt8 = 0x0a
let markerStart = "-- ".data(using: .utf8)!
let markerEnd = " --".data(using: .utf8)!
let newline = "\n".data(using: .utf8)!

/// A single file in an Archive.
public struct File {
	var name: String
	var data: Data
}

/// A collection of files.
public struct Archive {
    let files: [File]
    let comment: Data? = nil
    
//    public static func parse(data: Data) -> Archive {
//    }
	
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
	
	func formatFile(_ file: File) -> Data {
		var d = Data()
		d.append(markerStart)
		d.append(file.name.data(using: .utf8)!)
		d.append(markerEnd + newline)
		d.append(withFixedNewline(file.data))
		return d
	}
	
	func formatComment(_ comment: Data?) -> Data {
		var d = Data()
		if let c = comment {
			d.append(withFixedNewline(c))
		}
		return d
	}
}

/// If the given data is empty or ends in \n, returns the data as is.
/// Otherwise returns a copy of data with \n appended.
internal func withFixedNewline(_ d: Data) -> Data {
	if d.isEmpty || d.last! == newlineByte {
	    return d
    }
    var newData = Data(d)
    newData.append("\n".data(using: .utf8)!)
    return newData
}

internal func findNextFileMarker(data: Slice<Data>) -> (before: Slice<Data>, name: String, after: Slice<Data>)? {
	var idx = 0
	while true {
		if let markerLine = startsWithMarkerLine(data[idx...]) {
			return (before: data[...idx], name: markerLine.name, after: markerLine.after)
		}
		if let newlineIdx = data[idx...].firstIndex(of: newlineByte) {
			// try again
			idx = newlineIdx + 1
			continue
		}
		return nil // reached end
	}
}

// Checks whether data begins with a file marker line. If so,
// returns the filename and remaining data after the file marker line.
// Otherwise, returns nil.
internal func startsWithMarkerLine(_ data: Slice<Data>) -> (name: String, after: Slice<Data>)? {
	guard data.starts(with: markerStart) else {
		return nil
	}
	guard let lineEndIdx = data.firstIndex(of: newlineByte) else {
		return nil
	}
	let line = data.prefix(upTo: lineEndIdx)
	
	guard endsWithMarkerEnd(line) else {
		return nil
	}
	
	// Ensure the white space at the end of the start marker and the
	// end marker doesn't overlap.
	guard line.count >= markerStart.count + markerEnd.count else {
		return nil
	}
	
	// Extract the filename.
	let name = line[markerStart.count..<line.endIndex-markerEnd.count]
	// TODO: is it possible to construct String from Slice<Data>?
	guard let name = String(data: Data(name), encoding: .utf8)?
			.trimmingCharacters(in: CharacterSet.whitespaces) else {
		return nil
	}
	
	return (name, data[lineEndIdx+1..<data.endIndex])
}

// Does the line end with the end marker?
internal func endsWithMarkerEnd(_ line: Slice<Data>) -> Bool {
	guard line.count >= markerEnd.count else {
		return false
	}
	// Example:
	// -- name --
	// 0123456789; endIndex=10; markerEnd.count=3; 10-3=7; 7..<10
	return line[line.endIndex-markerEnd.count..<line.endIndex].elementsEqual(markerEnd)
}
