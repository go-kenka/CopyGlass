enum ClipboardItemStoreSQL {
    static let createFTSTable = """
    CREATE VIRTUAL TABLE IF NOT EXISTS clipboard_items_fts
    USING fts5(
        content,
        content_preview,
        search_base,
        search_pinyin,
        content='clipboard_items',
        content_rowid='rowid',
        tokenize='unicode61 remove_diacritics 2'
    );
    """

    static let createFTSInsertTrigger = """
    CREATE TRIGGER IF NOT EXISTS clipboard_items_ai AFTER INSERT ON clipboard_items BEGIN
        INSERT INTO clipboard_items_fts(rowid, content, content_preview, search_base, search_pinyin)
        VALUES (new.rowid, new.content, new.content_preview, new.search_base, new.search_pinyin);
    END;
    """

    static let createFTSDeleteTrigger = """
    CREATE TRIGGER IF NOT EXISTS clipboard_items_ad AFTER DELETE ON clipboard_items BEGIN
        INSERT INTO clipboard_items_fts(clipboard_items_fts, rowid, content, content_preview, search_base, search_pinyin)
        VALUES ('delete', old.rowid, old.content, old.content_preview, old.search_base, old.search_pinyin);
    END;
    """

    static let createFTSUpdateTrigger = """
    CREATE TRIGGER IF NOT EXISTS clipboard_items_au AFTER UPDATE ON clipboard_items BEGIN
        INSERT INTO clipboard_items_fts(clipboard_items_fts, rowid, content, content_preview, search_base, search_pinyin)
        VALUES ('delete', old.rowid, old.content, old.content_preview, old.search_base, old.search_pinyin);
        INSERT INTO clipboard_items_fts(rowid, content, content_preview, search_base, search_pinyin)
        VALUES (new.rowid, new.content, new.content_preview, new.search_base, new.search_pinyin);
    END;
    """

    static let rebuildFTS = "INSERT INTO clipboard_items_fts(clipboard_items_fts) VALUES ('rebuild');"

    static func fetchRecent(summary: Bool, filteredByRetention: Bool) -> String {
        let columns = summary
            ? "id, type, content_preview, image_thumb, date, appBundleID"
            : "id, type, content, rtf, image, date, appBundleID"
        let whereClause = filteredByRetention ? "\nWHERE date >= ?" : ""
        return """
        SELECT \(columns)
        FROM clipboard_items\(whereClause)
        ORDER BY date DESC
        LIMIT ?;
        """
    }

    static func search(summary: Bool, filteredByRetention: Bool) -> String {
        let columns = summary
            ? "ci.id, ci.type, ci.content_preview, ci.image_thumb, ci.date, ci.appBundleID"
            : "ci.id, ci.type, ci.content, ci.rtf, ci.image, ci.date, ci.appBundleID"
        let retentionClause = filteredByRetention ? "AND ci.date >= ?\n" : ""
        return """
        SELECT \(columns)
        FROM clipboard_items_fts
        JOIN clipboard_items ci ON ci.rowid = clipboard_items_fts.rowid
        WHERE clipboard_items_fts MATCH ?
        \(retentionClause)ORDER BY ci.date DESC
        LIMIT ?;
        """
    }

    static func ftsQuery(for query: String) -> String? {
        let normalized = query
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        var tokens = ftsTokens(in: normalized)
        let pinyin = query.pinyinSearchText()
        if pinyin != normalized {
            tokens.append(contentsOf: ftsTokens(in: pinyin))
        }
        var seen = Set<String>()
        let uniqueTokens = tokens.filter { token in
            guard !seen.contains(token) else { return false }
            seen.insert(token)
            return true
        }
        guard !uniqueTokens.isEmpty else { return nil }
        return uniqueTokens.map { "\"\($0)\"*" }.joined(separator: " ")
    }

    private static func ftsTokens(in text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for character in text {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}
