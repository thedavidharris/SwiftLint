import Foundation
import SourceKittenFramework

public struct StatementPositionRule: CorrectableRule, ConfigurationProviderRule {
    public var configuration = StatementConfiguration(statementMode: .default,
                                                      severity: SeverityConfiguration(.warning))

    public init() {}

    public static let description = RuleDescription(
        identifier: "statement_position",
        name: "Statement Position",
        description: "Else and catch should be on the same line, one space after the previous " +
                     "declaration.",
        kind: .style,
        nonTriggeringExamples: [
            "} else if {",
            "} else {",
            "} catch {",
            "\"}else{\"",
            "struct A { let catchphrase: Int }\nlet a = A(\n catchphrase: 0\n)",
            "struct A { let `catch`: Int }\nlet a = A(\n `catch`: 0\n)"
        ],
        triggeringExamples: [
            "↓}else if {",
            "↓}  else {",
            "↓}\ncatch {",
            "↓}\n\t  catch {"
        ],
        corrections: [
            "↓}\n else {\n": "} else {\n",
            "↓}\n   else if {\n": "} else if {\n",
            "↓}\n catch {\n": "} catch {\n"
        ]
    )

    public static let uncuddledDescription = RuleDescription(
        identifier: "statement_position",
        name: "Statement Position",
        description: "Else and catch should be on the next line, with equal indentation to the " +
                     "previous declaration.",
        kind: .style,
        nonTriggeringExamples: [
            "  }\n  else if {",
            "    }\n    else {",
            "  }\n  catch {",
            "  }\n\n  catch {",
            "\n\n  }\n  catch {",
            "\"}\nelse{\"",
            "struct A { let catchphrase: Int }\nlet a = A(\n catchphrase: 0\n)",
            "struct A { let `catch`: Int }\nlet a = A(\n `catch`: 0\n)"
        ],
        triggeringExamples: [
            "↓  }else if {",
            "↓}\n  else {",
            "↓  }\ncatch {",
            "↓}\n\t  catch {"
        ],
        corrections: [
            "  }else if {": "  }\n  else if {",
            "}\n  else {": "}\nelse {",
            "  }\ncatch {": "  }\n  catch {",
            "}\n\t  catch {": "}\ncatch {"
        ]
    )

    public func validate(file: SwiftLintFile) -> [StyleViolation] {
        switch configuration.statementMode {
        case .default:
            return defaultValidate(file: file)
        case .uncuddledElse:
            return uncuddledValidate(file: file)
        }
    }

    public func correct(file: SwiftLintFile) -> [Correction] {
        switch configuration.statementMode {
        case .default:
            return defaultCorrect(file: file)
        case .uncuddledElse:
            return uncuddledCorrect(file: file)
        }
    }
}

// Default Behaviors
private extension StatementPositionRule {
    // match literal '}'
    // followed by 1) nothing, 2) two+ whitespace/newlines or 3) newlines or tabs
    // followed by 'else' or 'catch' literals
    static let defaultPattern = "\\}(?:[\\s\\n\\r]{2,}|[\\n\\t\\r]+)?\\b(else|catch)\\b"

    func defaultValidate(file: SwiftLintFile) -> [StyleViolation] {
        return defaultViolationRanges(in: file, matching: type(of: self).defaultPattern).compactMap { range in
            StyleViolation(ruleDescription: type(of: self).description,
                           severity: configuration.severity.severity,
                           location: Location(file: file, characterOffset: range.location))
        }
    }

    func defaultViolationRanges(in file: SwiftLintFile, matching pattern: String) -> [NSRange] {
        return file.match(pattern: pattern).filter { _, syntaxKinds in
            return syntaxKinds.starts(with: [.keyword])
        }.compactMap { $0.0 }
    }

    func defaultCorrect(file: SwiftLintFile) -> [Correction] {
        let violations = defaultViolationRanges(in: file, matching: type(of: self).defaultPattern)
        let matches = file.ruleEnabled(violatingRanges: violations, for: self)
        if matches.isEmpty { return [] }
        let regularExpression = regex(type(of: self).defaultPattern)
        let description = type(of: self).description
        var corrections = [Correction]()
        var contents = file.contents
        for range in matches.reversed() {
            contents = regularExpression.stringByReplacingMatches(in: contents, options: [], range: range,
                                                                  withTemplate: "} $1")
            let location = Location(file: file, characterOffset: range.location)
            corrections.append(Correction(ruleDescription: description, location: location))
        }
        file.write(contents)
        return corrections
    }
}

// Uncuddled Behaviors
private extension StatementPositionRule {
    func uncuddledValidate(file: SwiftLintFile) -> [StyleViolation] {
        return uncuddledViolationRanges(in: file).compactMap { range in
            StyleViolation(ruleDescription: type(of: self).uncuddledDescription,
                           severity: configuration.severity.severity,
                           location: Location(file: file, characterOffset: range.location))
        }
    }

    // match literal '}'
    // preceded by whitespace (or nothing)
    // followed by 1) nothing, 2) two+ whitespace/newlines or 3) newlines or tabs
    // followed by newline and the same amount of whitespace then 'else' or 'catch' literals
    static let uncuddledPattern = "([ \t]*)\\}(\\n+)?([ \t]*)\\b(else|catch)\\b"

    static let uncuddledRegex = regex(uncuddledPattern, options: [])

    static func uncuddledMatchValidator(contents: StringView) -> ((NSTextCheckingResult)
        -> NSTextCheckingResult?) {
            return { match in
                if match.numberOfRanges != 5 {
                    return match
                }
                if match.range(at: 2).length == 0 {
                    return match
                }
                let range1 = match.range(at: 1)
                let range2 = match.range(at: 3)
                let whitespace1 = contents.string.substring(from: range1.location, length: range1.length)
                let whitespace2 = contents.string.substring(from: range2.location, length: range2.length)
                if whitespace1 == whitespace2 {
                    return nil
                }
                return match
            }
    }

    static func uncuddledMatchFilter(contents: StringView,
                                     syntaxMap: SwiftLintSyntaxMap) -> ((NSTextCheckingResult) -> Bool) {
        return { match in
            let range = match.range
            guard let matchRange = contents.NSRangeToByteRange(start: range.location,
                                                               length: range.length) else {
                return false
            }
            return syntaxMap.kinds(inByteRange: matchRange) == [.keyword]
        }
    }

    func uncuddledViolationRanges(in file: SwiftLintFile) -> [NSRange] {
        let contents = file.stringView
        let syntaxMap = file.syntaxMap
        let matches = StatementPositionRule.uncuddledRegex.matches(in: file)
        let validator = type(of: self).uncuddledMatchValidator(contents: contents)
        let filterMatches = type(of: self).uncuddledMatchFilter(contents: contents, syntaxMap: syntaxMap)

        let validMatches = matches.compactMap(validator).filter(filterMatches).map({ $0.range })

        return validMatches
    }

    func uncuddledCorrect(file: SwiftLintFile) -> [Correction] {
        var contents = file.contents
        let syntaxMap = file.syntaxMap
        let matches = StatementPositionRule.uncuddledRegex.matches(in: file)
        let validator = type(of: self).uncuddledMatchValidator(contents: file.stringView)
        let filterRanges = type(of: self).uncuddledMatchFilter(contents: file.stringView, syntaxMap: syntaxMap)

        let validMatches = matches.compactMap(validator).filter(filterRanges)
                  .filter { !file.ruleEnabled(violatingRanges: [$0.range], for: self).isEmpty }
        if validMatches.isEmpty { return [] }
        let description = type(of: self).uncuddledDescription
        var corrections = [Correction]()

        for match in validMatches.reversed() {
            let range1 = match.range(at: 1)
            let range2 = match.range(at: 3)
            let newlineRange = match.range(at: 2)
            var whitespace = contents.bridge().substring(with: range1)
            let newLines: String
            if newlineRange.location != NSNotFound {
               newLines = contents.bridge().substring(with: newlineRange)
            } else {
                newLines = ""
            }
            if !whitespace.hasPrefix("\n") && newLines != "\n" {
                whitespace.insert("\n", at: whitespace.startIndex)
            }
            contents = contents.bridge().replacingCharacters(in: range2, with: whitespace)
            let location = Location(file: file, characterOffset: match.range.location)
            corrections.append(Correction(ruleDescription: description, location: location))
        }

        file.write(contents)
        return corrections
    }
}
