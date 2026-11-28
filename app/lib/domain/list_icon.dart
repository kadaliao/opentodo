/// A list's `emoji` column holds an emoji (or a character or two typed in),
/// or `sf:<name>` for an SF Symbol the Swift version draws. This version
/// has no SF Symbols: such a list shows its default icon, not the text.
const listSymbolPrefix = 'sf:';

/// The emoji to show for a list's stored icon; null for none or a symbol.
String? listEmoji(String? stored) =>
    stored == null || stored.isEmpty || stored.startsWith(listSymbolPrefix) ? null : stored;
