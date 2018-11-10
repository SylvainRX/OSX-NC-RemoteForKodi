//
//  PrintDebugTools.swift
//
//  Created by Sylvain on 04/09/2018.
//  Copyright © 2018 Sylvain. All rights reserved.
//

import Foundation


class Print {
    static func debug(_ message: String = "", filePath: String = #file, line: Int = #line, function: String = #function) {
        #if DEBUG
        var file = filePath
        if let debugFilter = ProcessInfo.processInfo.environment["DEBUG_FILTER"] {
            let subrange = file.startIndex..<file.index(file.startIndex, offsetBy: debugFilter.count)
            file.removeSubrange(subrange)
        }
        var debugLine = "DEBUG: \(file): \(line) \(function)"
        if message != "" {
            debugLine += ": \n\(message)"
        }
        print(debugLine)
        #endif
    }
    
    static func error(_ error: Error, filePath: String = #file, line: Int = #line, function: String = #function) {
        var file = filePath
        if let debugFilter = ProcessInfo.processInfo.environment["DEBUG_FILTER"] {
            let subrange = file.startIndex..<file.index(file.startIndex, offsetBy: debugFilter.count)
            file.removeSubrange(subrange)
        }
        var debugLine = "ERROR: \(file): \(line) \(function)"
        if error.localizedDescription != "" {
            debugLine += ": \t \(error.localizedDescription)"
        }
        print(debugLine)
    }
    
    static func debugXml(_ message: String = "", filePath: String = #file, line: Int = #line, function: String = #function) {
        #if DEBUG
        let xmlFormater = XMLFormater(withXML: message)
        self.debug(xmlFormater.format(), filePath: filePath, line: line, function: function)
        #endif
    }
    
    static func debugJson(_ message: String = "", filePath: String = #file, line: Int = #line, function: String = #function) {
        #if DEBUG
        let jsonFormater = JSONFormater(withJSON: message)
        self.debug(jsonFormater.format(), filePath: filePath, line: line, function: function)
        #endif
    }
    
    func clearConsole() {
        #if DEBUG
        var clearString = ""
        for _ in 1..<200 {
            clearString += "\n"
        }
        print(clearString)
        #endif
    }
}


class XMLFormater: NSObject, XMLParserDelegate {
    var xmlString: String
    var formattedXml = ""
    var xmlDeclaration: String?
    var level: Int = 0
    var currentElementName: String?
    var foundCharacters: String = ""
    
    init(withXML xmlString: String) {
        self.xmlString = xmlString
    }
    
    func format() -> String {
        self.xmlString = self.xmlString.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        // Add XML declaration to the formated document
        let regex = try? NSRegularExpression(pattern: "<\\?xml.*\\?>", options: [])
        let matches = regex?.matches(in: self.xmlString, options: [], range: NSRange(location: 0, length: self.xmlString.count))
        if matches!.count != 0 {
            let range = matches![0].range(at: 0)
            let startIndex = self.xmlString.index(self.xmlString.startIndex, offsetBy: range.location)
            let index = self.xmlString.index(startIndex, offsetBy: range.length)
            self.xmlDeclaration = String(self.xmlString[..<index])
        }
        
        let data = self.xmlString.data(using: String.Encoding(rawValue: String.Encoding.utf8.rawValue))!
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = self
        let isXmlValid = xmlParser.parse()
        if !isXmlValid {
            self.formattedXml = "\(self.xmlString)\n<!-- Error : Invalid XML document -->"
        }
        
        return self.formattedXml
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        self.formattedXml += "\n"
        for _ in 0..<self.level {
            self.formattedXml += "    "
        }
        self.level += 1
        self.formattedXml += "<\(elementName)"
        for attribute in attributeDict {
            self.formattedXml += " \(attribute.key)=\"\(attribute.value)\""
        }
        self.formattedXml += ">"
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let string = string.replacingOccurrences(of: "&", with: "&amp;")
        self.foundCharacters += string
    }
    
    func parser(_ parser: XMLParser, foundComment comment: String) {
        self.formattedXml += "\n"
        for _ in 0..<self.level {
            self.formattedXml += "    "
        }
        self.formattedXml += "<!--\(comment)-->"
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        self.level -= 1
        if self.foundCharacters.count != 0 {
            self.formattedXml += self.foundCharacters
            self.foundCharacters = ""
        }
        else {
            self.formattedXml += "\n"
            for _ in 0..<self.level {
                self.formattedXml += "    "
            }
        }
        self.formattedXml += "</\(elementName)>"
    }
    
    func parserDidEndDocument(_ parser: XMLParser) {
        if self.xmlDeclaration != nil {
            self.formattedXml = self.xmlDeclaration! + self.formattedXml
        }
        else {
            self.formattedXml += self.formattedXml.dropFirst()
        }
    }
}


class JSONFormater: NSObject {
    var formattedJson = ""
    var level: Int = 0
    var jsonString: String
    
    init(withJSON jsonString: String) {
        self.jsonString = jsonString
    }
    
    func format() -> String {
        self.jsonString = self.jsonString.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        if let anEncoding = jsonString.data(using: String.Encoding.utf8) {
            guard let jsonObject = try? JSONSerialization.jsonObject(with: anEncoding, options: []) as! [String: Any] else {
                self.formattedJson = "\(jsonString)\n{ \"Error\": \"Invalid JSON document\"}"
                return self.formattedJson
            }
            self.formatElement(jsonObject)
            self.formattedJson = "{\n\(self.formattedJson)\n}"
        }
        
        return self.formattedJson
    }
    
    func formatElement(_ jsonElement: [String: Any]) {
        self.level += 1
        for (index, jsonKeyValue) in jsonElement.enumerated() {
            self.indent()
            if let jsonString = jsonKeyValue.value as? String {
                self.formattedJson += "\"\(jsonKeyValue.key)\" : "
                self.formattedJson += "\"\(jsonString)\""
            }
            if let jsonNumber = jsonKeyValue.value as? Double {
                self.formattedJson += "\"\(jsonKeyValue.key)\" : "
                if floor(jsonNumber) == jsonNumber {
                    self.formattedJson += "\(Int(jsonNumber))"
                }
                else {
                    self.formattedJson += "\(jsonNumber)"
                }
            }
            if let jsonBool = jsonKeyValue.value as? Bool {
                self.formattedJson += "\"\(jsonKeyValue.key)\" : "
                self.formattedJson += "\(jsonBool)"
            }
            else if let jsonObject = jsonKeyValue.value as? [String: Any] {
                self.formattedJson += "\"\(jsonKeyValue.key)\" : {\n"
                self.formatElement(jsonObject)
                self.formattedJson += "\n"
                self.indent()
                self.formattedJson += "}"
            }
            else if let jsonArray = jsonKeyValue.value as? [[String: Any]] {
                self.formattedJson += "\"\(jsonKeyValue.key)\" : [\n"
                self.level += 1
                self.indent()
                for (index, jsonKeyValue) in jsonArray.enumerated() {
                    self.formattedJson += "{\n"
                    self.formatElement(jsonKeyValue)
                    self.formattedJson += "\n"
                    self.indent()
                    self.formattedJson += "}"
                    if index + 1 < jsonArray.count {
                        self.formattedJson += ",\n"
                        self.indent()
                    }
                }
                self.formattedJson += "\n"
                self.level -= 1
                self.indent()
                self.formattedJson += "]"
            }
            if index + 1 < jsonElement.count {self.formattedJson += ",\n"}
        }
        self.level -= 1
    }
    
    func indent(str: String = " ") {
        for _ in 0..<self.level*4 {
            self.formattedJson += str
        }
    }
}
