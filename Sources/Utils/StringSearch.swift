import Foundation

extension String {
    func normalizedSearchText() -> String {
        folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }
    
    func pinyinSearchText() -> String {
        let mutable = NSMutableString(string: self) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
        return (mutable as String)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }
    
    func matchesSearch(_ query: String) -> Bool {
        let q = query.normalizedSearchText()
        if q.isEmpty { return true }
        let base = normalizedSearchText()
        if base.contains(q) { return true }
        let pinyin = pinyinSearchText()
        return pinyin.contains(q)
    }
    
    var isLikelyPinyinQuery: Bool {
        let q = normalizedSearchText()
        return !q.isEmpty && q.allSatisfy { c in
            c.isASCII && (c.isLetter || c.isNumber)
        }
    }
}
