# Renders transcript lines (from ScriptText) as escaped HTML: speaker names,
# stage directions and locations get their own styles, and search terms are
# wrapped in <mark>. Every piece of transcript text goes through `h`, so the
# transcripts are never trusted as HTML.
module ScriptHelper
  INLINE_DIRECTION = /(\([^)]*\)|\[[^\]]*\])/

  # lines: ScriptText::Line list. highlight: Range of line indexes to mark as
  # the matching scene (the first gets id="match" so links can jump to it).
  def script_lines(lines, terms: [], highlight: nil)
    pattern = ScriptText.term_pattern(terms)
    first_highlight = true

    safe_join(lines.map do |line|
      classes = ["line"]
      classes << "line--dialogue" if line.dialogue?
      classes << "line--location" if line.location?
      classes << "line--direction" if line.direction?
      attrs = {}
      if highlight&.cover?(line.index)
        classes << "line--match"
        attrs[:id] = "match" if first_highlight
        first_highlight = false
      end

      content_tag(:p, class: classes, **attrs) do
        speaker = line.dialogue? ? content_tag(:span, line.speaker, class: "speaker") : "".html_safe
        speaker + script_inline(line.text, pattern)
      end
    end)
  end

  # Text with inline (stage directions) and [locations] styled, and terms marked.
  def script_inline(text, pattern = nil)
    safe_join(text.split(INLINE_DIRECTION).map do |part|
      next "".html_safe if part.empty?

      marked = mark_terms(part, pattern)
      part.match?(/\A[(\[]/) ? content_tag(:span, marked, class: "direction") : marked
    end)
  end

  # Escapes text and wraps each match of pattern in <mark>.
  def mark_terms(text, pattern)
    return ERB::Util.html_escape(text) unless pattern

    pieces = []
    last = 0
    text.to_enum(:scan, pattern).each do
      m = Regexp.last_match
      pieces << ERB::Util.html_escape(text[last...m.begin(0)]) << content_tag(:mark, m[0])
      last = m.end(0)
    end
    pieces << ERB::Util.html_escape(text[last..])
    safe_join(pieces)
  end

  # Line index range in the full episode text covered by an excerpt of a chunk.
  def chunk_line_range(episode_text, chunk, first_line, count)
    start = episode_text.index(chunk.content)
    return unless start

    base = episode_text[0...start].count("\n")
    (base + first_line)...(base + first_line + count)
  end
end
