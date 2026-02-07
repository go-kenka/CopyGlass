import Foundation
import AppKit

final class HighlightRenderer {
    static let shared = HighlightRenderer()
    
    private let attributedCache = NSCache<NSString, NSAttributedString>()
    private let pinyinMapCache = NSCache<NSString, PinyinMap>()
    
    private init() {
        attributedCache.countLimit = 1200
        pinyinMapCache.countLimit = 600
    }
    
    func render(text: String, itemID: UUID, query: String, baseColor: NSColor? = nil) -> NSAttributedString {
        let qRaw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = qRaw.normalizedSearchText()
        if q.isEmpty {
            let base = NSMutableAttributedString(string: text)
            if let baseColor {
                base.addAttribute(.foregroundColor, value: baseColor, range: NSRange(location: 0, length: (text as NSString).length))
            }
            return base
        }
        
        let cacheKey = "\(itemID.uuidString)|\(q)|\(baseColor?.description ?? "-")" as NSString
        if let cached = attributedCache.object(forKey: cacheKey) {
            return cached
        }
        
        let result = NSMutableAttributedString(string: text)
        if let baseColor {
            result.addAttribute(.foregroundColor, value: baseColor, range: NSRange(location: 0, length: (text as NSString).length))
        }
        
        let highlightColor = NSColor(calibratedRed: 0.55, green: 0.10, blue: 0.10, alpha: 1.0)
        
        let matches = rangesInText(needle: qRaw, haystack: text)
        if !matches.isEmpty {
            for r in matches {
                result.addAttribute(.foregroundColor, value: highlightColor, range: r)
            }
            attributedCache.setObject(result, forKey: cacheKey)
            return result
        }
        
        if q.isLikelyPinyinQuery {
            let mapKey = itemID.uuidString as NSString
            let map: PinyinMap
            if let cached = pinyinMapCache.object(forKey: mapKey) {
                map = cached
            } else {
                map = PinyinMap(text: text)
                pinyinMapCache.setObject(map, forKey: mapKey)
            }
            
            let queryRanges = rangesInPinyin(needle: q, haystack: map.pinyin)
            if !queryRanges.isEmpty {
                for qr in queryRanges {
                    let start = qr.location
                    let end = qr.location + qr.length
                    for i in 0..<map.count where map.pinyinStart[i] < end && map.pinyinEnd[i] > start {
                        result.addAttribute(.foregroundColor, value: highlightColor, range: map.charRanges[i])
                    }
                }
            }
        }
        
        attributedCache.setObject(result, forKey: cacheKey)
        return result
    }
    
    private func rangesInText(needle: String, haystack: String) -> [NSRange] {
        let n = needle.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { return [] }
        let hs = haystack as NSString
        var out: [NSRange] = []
        var searchRange = NSRange(location: 0, length: hs.length)
        while true {
            let r = hs.range(of: n, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
            if r.location == NSNotFound { break }
            out.append(r)
            let nextLoc = r.location + max(1, r.length)
            if nextLoc >= hs.length { break }
            searchRange = NSRange(location: nextLoc, length: hs.length - nextLoc)
        }
        return out
    }
    
    private func rangesInPinyin(needle: String, haystack: String) -> [NSRange] {
        let hs = haystack as NSString
        let n = needle as NSString
        if n.length == 0 || hs.length == 0 { return [] }
        var out: [NSRange] = []
        var searchRange = NSRange(location: 0, length: hs.length)
        while true {
            let r = hs.range(of: n as String, options: [], range: searchRange)
            if r.location == NSNotFound { break }
            out.append(r)
            let nextLoc = r.location + max(1, r.length)
            if nextLoc >= hs.length { break }
            searchRange = NSRange(location: nextLoc, length: hs.length - nextLoc)
        }
        return out
    }
}

final class PinyinMap: NSObject {
    let pinyin: String
    let charRanges: [NSRange]
    let pinyinStart: [Int]
    let pinyinEnd: [Int]
    let count: Int
    
    init(text: String) {
        let ns = text as NSString
        let len = ns.length
        var starts: [Int] = []
        var ends: [Int] = []
        var ranges: [NSRange] = []
        starts.reserveCapacity(len)
        ends.reserveCapacity(len)
        ranges.reserveCapacity(len)
        
        var p = ""
        p.reserveCapacity(len * 2)
        
        for i in 0..<len {
            let r = NSRange(location: i, length: 1)
            let ch = ns.substring(with: r)
            let s = p.count
            p.append(ch.pinyinSearchText())
            let e = p.count
            starts.append(s)
            ends.append(e)
            ranges.append(r)
        }
        
        pinyin = p
        charRanges = ranges
        pinyinStart = starts
        pinyinEnd = ends
        count = len
    }
}
