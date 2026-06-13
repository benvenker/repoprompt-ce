import Foundation

public extension String {
    static func splitContentPreservingLineEndings(_ content: String) -> ([String], String) {
        var lines: [String] = []
        var currentLine = ""
        var detectedLineEnding = "\n"
        var index = content.startIndex

        while index < content.endIndex {
            let char = content[index]
            if char == "\r" {
                let nextIndex = content.index(after: index)
                if nextIndex < content.endIndex, content[nextIndex] == "\n" {
                    currentLine.append("\r\n")
                    detectedLineEnding = "\r\n"
                    lines.append(currentLine)
                    currentLine = ""
                    index = content.index(after: nextIndex)
                } else {
                    currentLine.append("\r")
                    detectedLineEnding = "\r"
                    lines.append(currentLine)
                    currentLine = ""
                    index = nextIndex
                }
            } else if char == "\n" {
                currentLine.append("\n")
                detectedLineEnding = "\n"
                lines.append(currentLine)
                currentLine = ""
                index = content.index(after: index)
            } else {
                currentLine.append(char)
                index = content.index(after: index)
            }
        }

        if !currentLine.isEmpty || content.isEmpty {
            lines.append(currentLine)
        }

        return (lines, detectedLineEnding)
    }

    static func splitContentPreservingAllLineEndings(_ content: String) -> [(line: String, ending: String)] {
        var pairs: [(line: String, ending: String)] = []
        var currentLine = ""
        var index = content.startIndex

        while index < content.endIndex {
            let char = content[index]
            if char == "\r" {
                let nextIndex = content.index(after: index)
                if nextIndex < content.endIndex, content[nextIndex] == "\n" {
                    pairs.append((currentLine, "\r\n"))
                    currentLine = ""
                    index = content.index(after: nextIndex)
                } else {
                    pairs.append((currentLine, "\r"))
                    currentLine = ""
                    index = nextIndex
                }
            } else if char == "\n" {
                pairs.append((currentLine, "\n"))
                currentLine = ""
                index = content.index(after: index)
            } else {
                currentLine.append(char)
                index = content.index(after: index)
            }
        }

        if !currentLine.isEmpty || content.isEmpty {
            pairs.append((currentLine, ""))
        }

        return pairs
    }
}
