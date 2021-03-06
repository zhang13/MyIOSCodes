//
//  SourceEditorCommand.swift
//  MyCommentExt
//
//  Created by Richard on 2016/12/31.
//  Copyright © 2016年 Richard. All rights reserved.
//

/*
import Foundation
import XcodeKit

class SourceEditorCommand: NSObject, XCSourceEditorCommand {
    
    func perform(with invocation: XCSourceEditorCommandInvocation, completionHandler: @escaping (Error?) -> Void ) -> Void {
        
        let buffer = invocation.buffer // 调用处获取到缓冲
        print(buffer.selections)
        // 选择文本范围，由于没有选择，那么就是光标位置
        if let insertionPoint = buffer.selections[0] as? XCSourceTextRange {
            let currentLine = insertionPoint.start.line // 选择所在行
            buffer.lines.insert("// More Awesome", at: currentLine) // 插入文本
        }
        
        completionHandler(nil)  // 处理完成，通知XCode
        
    }
}
*/


import Foundation
import XcodeKit

enum CommentStatus {
    case Plain
    case Unpair
    case Pair(range: NSRange)
}

class SourceEditorCommand: NSObject, XCSourceEditorCommand {
    
    func perform(with invocation: XCSourceEditorCommandInvocation, completionHandler: @escaping (Error?) -> Swift.Void ) {
        
        let buffer = invocation.buffer
        let selections = buffer.selections
        
        selections.forEach {
            let range = $0 as! XCSourceTextRange
            print("forEach", range.start, range.end)
            if range.start.line == range.end.line && range.start.column == range.end.column {
                let fake: XCSourceTextRange = range
                let lineText = buffer.lines[fake.start.line] as! String
                
                fake.start.column = 0
                fake.end.column = lineText.distance(from: lineText.startIndex, to: lineText.endIndex) - 1
                
                if fake.end.column > fake.start.column {
                    let ref = handle(range: fake, inBuffer: buffer)
                    if ref == true {
                        range.end.column += 4
                    }
                }
            } else {
                let ref = handle(range: range, inBuffer: buffer)
                if ref == true {
                    range.end.column += 4
                }
            }
        }
        
        completionHandler(nil)
    }
    
    func handle(range: XCSourceTextRange, inBuffer buffer: XCSourceTextBuffer) -> Bool {
        let selectedText = text(inRange: range, inBuffer: buffer)
        let status = selectedText.commentStatus
        
        switch status {
        case .Unpair:
            break
        case .Plain:
            insert(position: range.end, length: 1, with: "*/", inBuffer: buffer)
            insert(position: range.start, length: 0, with: "/*", inBuffer: buffer)
            return true
        case .Pair(let commentedRange):
            let startPair = position(range.start, offsetBy: commentedRange.location, inBuffer: buffer)
            let endPair = position(range.start, offsetBy: commentedRange.location + commentedRange.length, inBuffer: buffer)
            replace(position: endPair, length: -("*/".characters.count), with: "", inBuffer: buffer)
            replace(position: startPair, length: "/*".characters.count, with: "", inBuffer: buffer)
        }
        return false
    }
    
    func text(inRange textRange: XCSourceTextRange, inBuffer buffer: XCSourceTextBuffer) -> String {
        if textRange.start.line == textRange.end.line {
            let lineText = buffer.lines[textRange.start.line] as! String
            let from = lineText.index(lineText.startIndex, offsetBy: textRange.start.column)
            let to = lineText.index(lineText.startIndex, offsetBy: textRange.end.column)
            return lineText[from...to]
        }
        
        var text = ""
        
        for aLine in textRange.start.line...textRange.end.line {
            let lineText = buffer.lines[aLine] as! String
            
            switch aLine {
            case textRange.start.line:
                text += lineText.substring(from: lineText.index(lineText.startIndex, offsetBy: textRange.start.column))
            case textRange.end.line:
                text += lineText.substring(to: lineText.index(lineText.startIndex, offsetBy: textRange.end.column + 1))
            default:
                text += lineText
            }
        }
        
        return text
    }
    
    func position(_ i: XCSourceTextPosition, offsetBy: Int, inBuffer buffer: XCSourceTextBuffer) -> XCSourceTextPosition {
        var aLine = i.line
        var aLineColumn = i.column
        var n = offsetBy
        
        repeat {
            let aLineCount = (buffer.lines[aLine] as! String).characters.count
            let leftInLine = aLineCount - aLineColumn
            
            if leftInLine <= n {
                n -= leftInLine
            } else {
                return XCSourceTextPosition(line: aLine, column: aLineColumn + n)
            }
            
            aLine += 1
            aLineColumn = 0
        } while aLine < buffer.lines.count
        
        return i
    }
    
    func replace(position: XCSourceTextPosition, length: Int, with newElements: String, inBuffer buffer: XCSourceTextBuffer) {
        var lineText = buffer.lines[position.line] as! String
        
        var start = lineText.index(lineText.startIndex, offsetBy: position.column)
        var end = lineText.index(start, offsetBy: length)
        
        if length < 0 {
            swap(&start, &end)
        }
        
        lineText.replaceSubrange(start..<end, with: newElements)
        lineText.remove(at: lineText.index(before: lineText.endIndex)) //remove end "\n"
        
        buffer.lines[position.line] = lineText
    }
    
    func insert(position: XCSourceTextPosition, length: Int, with newElements: String, inBuffer buffer: XCSourceTextBuffer) {
        var lineText = buffer.lines[position.line] as! String
        
        var start = lineText.index(lineText.startIndex, offsetBy: position.column + length)
        
        if start >= lineText.endIndex {
            start = lineText.index(before: lineText.endIndex)
        }
        
        lineText.insert(contentsOf: newElements.characters, at: start)
        lineText.remove(at: lineText.index(before: lineText.endIndex)) //remove end "\n"
        
        buffer.lines[position.line] = lineText
    }
    
}

extension String {
    
    var commentedRange: NSRange? {
        do {
            let expression = try NSRegularExpression(pattern: "/\\*[\\s\\S]*\\*/", options: [])
            let matches = expression.matches(in: self, options: [], range: NSRange(location: 0, length: self.distance(from: self.startIndex, to: self.endIndex)))
            return matches.first?.range
        } catch {
        }
        return nil
    }
    
    var isUnpairCommented: Bool {
        if let i = characters.index(of: "*") {
            if i > startIndex && i < endIndex {
                if characters[index(before: i)] == "/" ||
                    characters[index(after: i)] == "/" {
                    return true
                }
            }
        }
        return false
    }
    
    var commentStatus: CommentStatus {
        if let range = commentedRange {
            return .Pair(range: range)
        }
        if isUnpairCommented {
            return .Unpair
        }
        return .Plain
    }
}

