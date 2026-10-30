import Foundation

var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
let detector = Detector()
let map = KeyboardMap()
expect(map.convert("ghbdtn", from: .en) == "привет", "English keys to Russian")
expect(map.convert("руддщ", from: .ru) == "hello", "Russian keys to English")
expect(map.convert("Ghbdtn", from: .en) == "Привет", "Preserve capitalization")
expect(map.convert("Привет", from: .ru) == "Ghbdtn", "Round trip capitalization")
expect(map.convert("foo@example", from: .en) == nil, "Do not transform email addresses")
expect(detector.correction("gh", from: .en, boundary: false) == nil, "Balanced mode waits for 3 characters")
expect(detector.correction("ghb", from: .en, boundary: false) == "при", "Recognize привет at third character")
expect(detector.correction("руд", from: .ru, boundary: false) == nil, "Ambiguous Russian fragment waits")
expect(detector.correction("рудд", from: .ru, boundary: false) == "hell", "Recognize English while typing")
expect(detector.correction("ghbdtn", from: .en, boundary: true) == "привет", "Word boundary Russian")
expect(detector.correction("руддщ", from: .ru, boundary: true) == "hello", "Word boundary English")
expect(detector.correction("hello", from: .en, boundary: true) == nil, "Keep valid English")
expect(detector.correction("привет", from: .ru, boundary: true) == nil, "Keep valid Russian")
expect(detector.correction("API", from: .en, boundary: false) == nil, "Preserve acronym")
expect(detector.correction("cat", from: .en, boundary: false) == nil, "Preserve short English word")
expect(detector.correction("in", from: .en, boundary: true) == nil, "Keep ambiguous two-letter word")
expect(detector.correction("ghbdtn123", from: .en, boundary: true) == nil, "Do not correct identifiers with digits")
expect(detector.correction(String(repeating: "g", count: 80), from: .en, boundary: false) == nil, "Bound retained token length")
detector.sensitivity = .fast
expect(detector.correction("GH", from: .en, boundary: false) == nil, "Fast mode preserves uppercase abbreviations")
expect(detector.correction("gh", from: .en, boundary: false) == "пр", "Fast mode detects at second character")
expect(detector.correction("щз", from: .ru, boundary: false) == "op", "Fast mode English two-character evidence")
detector.sensitivity = .careful
expect(detector.correction("ghbdtn", from: .en, boundary: false) == nil, "Careful mode waits for boundary")
expect(detector.correction("ghbdtn", from: .en, boundary: true) == "привет", "Careful mode converts at boundary")
detector.exceptions = ["ghbdtn"]
expect(detector.correction("Ghbdtn", from: .en, boundary: true) == nil, "Case-insensitive source exception")
detector.exceptions = ["привет"]
expect(detector.correction("ghbdtn", from: .en, boundary: true) == nil, "Target exception")
detector.exceptions = []
detector.customWords = ["богдан"]
expect(detector.correction(" ,", from: .en, boundary: true) == nil, "Ignore whitespace")
expect(detector.correction(",julfy", from: .en, boundary: true) == "богдан", "Custom dictionary recognizes name")
detector.spelling = { word, language in language == .en && word == "ghbdtn" }
expect(detector.correction("ghbdtn", from: .en, boundary: true) == nil, "System dictionary protects source word")
detector.spelling = { word, language in language == .ru && word == "тестовый" }
expect(detector.correction("ntcnjdsq", from: .en, boundary: true) == "тестовый", "System dictionary expands target vocabulary")
// Simulate the physical-key stream: after conversion subsequent keys use the new layout.
detector.spelling = nil; detector.sensitivity = .balanced
func simulate(_ physical: String, initial: Language) -> String {
    var output = ""; var current = initial; var converted = false
    for physicalKey in physical {
        let typed = current == .en ? String(physicalKey) : map.convert(String(physicalKey), from: .en)!
        output += typed
        if !converted, let corrected = detector.correction(output, from: current, boundary: false) {
            output = corrected; current = current.other; converted = true
        }
    }
    return output
}
expect(simulate("ghbdtn", initial: .en) == "привет", "Streaming Russian conversion does not lose subsequent letters")
expect(simulate("hello", initial: .ru) == "hello", "Streaming English conversion does not oscillate")
for valid in ["hello", "help", "program", "great", "create", "something", "english", "world", "return", "github"] {
    expect(simulate(valid, initial: .en) == valid, "Do not corrupt \(valid) while typing")
}
print("PASS: \(checks) detector checks")
