/// Strips inline Markdown formatting markers from [input], preserving the inner
/// text. For model-authored status/narrator lines and the pre-session brief,
/// which render as PLAIN text — the model intermittently emits *italics*,
/// **bold**, `code`, etc. that would otherwise show as literal characters
/// (e.g. "Status — *Asha's last session…*"). Handle at render, not by hoping
/// the model omits markup.
///
/// Handles: **bold**, __bold__, *italic*, _italic_ (snake_case safe),
/// `inline code`, ~~strike~~, [text](url) links, ![alt](img) images, and
/// leading ATX `#` headings. Does NOT reflow text or strip list bullets, so
/// multi-line content (the brief) keeps its structure.
String stripInlineMarkdown(String input) {
  if (input.isEmpty) return input;
  var s = input;

  // Images first: ![alt](url) -> alt
  s = s.replaceAllMapped(
      RegExp(r'!\[([^\]]*)\]\([^)]*\)'), (m) => m[1] ?? '');
  // Links: [text](url) -> text
  s = s.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1] ?? '');

  // Bold BEFORE italic so the doubled markers are consumed first.
  //   **text**
  s = s.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m[1] ?? '');
  //   __text__  (word-boundary aware so it never touches snake_case)
  s = s.replaceAllMapped(
      RegExp(r'(?<!\w)__(?=\S)(.+?)(?<=\S)__(?!\w)'), (m) => m[1] ?? '');

  // Strikethrough: ~~text~~
  s = s.replaceAllMapped(RegExp(r'~~(.+?)~~'), (m) => m[1] ?? '');

  // Italic: *text*  (asterisks don't occur intra-word in clinical prose)
  s = s.replaceAllMapped(RegExp(r'\*(.+?)\*'), (m) => m[1] ?? '');
  // Italic: _text_  (word-boundary aware — protects target_behavior, snake_case)
  s = s.replaceAllMapped(
      RegExp(r'(?<!\w)_(?=\S)(.+?)(?<=\S)_(?!\w)'), (m) => m[1] ?? '');

  // Inline code: `text`
  s = s.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m[1] ?? '');

  // Leading ATX heading markers at line starts: "## Title" -> "Title".
  s = s.replaceAllMapped(RegExp(r'(^|\n)#{1,6}[ \t]+'), (m) => m[1] ?? '');

  return s;
}
