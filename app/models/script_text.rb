# Parses raw transcript text ("PICARD: Make it so.", "(Data turns)",
# "[Bridge]") into lines for display, picks the most relevant few lines of a
# scene, and finds search terms to highlight. Pure Ruby; rendering lives in
# ScriptHelper.
class ScriptText
  Line = Data.define(:index, :speaker, :text) do
    def dialogue? = speaker.present?
    def location? = speaker.nil? && text.match?(/\A\[[^\]]+\]\z/)
    def direction? = speaker.nil? && text.match?(/\A\(.*\)\z/m)
  end

  # "LAFORGE: ...", "PICARD [OC]: ...", "Q: ...", "DAX'S MOTHER: ..."
  SPEAKER = /\A([A-Z][A-Z0-9'.\- ]{0,40}?(?:\s*\[[^\]]{1,20}\])?):\s*(.*)\z/m
  # The transcript site's header and footer, which aren't part of the script.
  HEADER = /\A[^\n]{0,300}?Original Airdate:\s*\d{1,2}\s+\w+,?\s+\d{4}\s*/m
  FOOTER = /\s*<Back to the episode listing.*\z/m

  STOPWORDS = %w[
    the and for that with this from what when where which who whom whose why how does did done
    episode episodes series season star trek scene scenes about into onto than then there their they
    them his her hers him she has have had was were are is be been being its it's not but can could
    would should will just also some any all one find show tell where's what's some someone something
    after before while during gets get got make makes made takes take tries try trying becomes become
    tng ds9 voy tos tas ent next generation deep space nine original animated
  ].to_set.freeze

  # Non-blank lines of `text`. Each Line's index is its position in
  # text.split("\n"), so ranges of indexes map back onto the raw text.
  def self.lines(text)
    raw = text.to_s.sub(FOOTER, "").gsub(/<br\s*\/?>/i, "")
    raw.split("\n").each_with_index.filter_map do |line, i|
      line = line.sub(HEADER, "") if i.zero?
      line = line.squish
      next if line.empty?

      if (m = line.match(SPEAKER))
        Line.new(index: i, speaker: m[1].squish, text: m[2])
      else
        Line.new(index: i, speaker: nil, text: line)
      end
    end
  end

  # Search terms worth highlighting: words of 3+ letters that aren't
  # stopwords, from any of the given strings, at most `max`. Each is cut to
  # a rough stem, since terms match the start of a word: "jokes" -> "joke"
  # also marks "joke" and "joking", "learning" -> "learn" marks "learned".
  def self.terms(*texts, max: 12)
    texts.compact.flat_map { _1.to_s.downcase.scan(/[a-z][a-z0-9']{2,}/) }
      .map { _1.delete_suffix("'s").delete("'") }
      .reject { STOPWORDS.include?(_1) || _1.length < 3 }
      .map { stem(_1) }
      .uniq.first(max)
  end

  # Drops one common ending (-ing, -ed, -es, -s, not -ss) when at least four
  # letters are left, so "lives" -> "live" but "bus" stays.
  def self.stem(word)
    return word if word.end_with?("ss")

    %w[ing ed es s].each do |ending|
      base = word.delete_suffix(ending)
      return base if base != word && base.length >= 4
    end
    word
  end

  # Regexp matching any of the terms at the start of a word ("assassin"
  # matches "assassinate"), or nil when there are none.
  def self.term_pattern(terms)
    return if terms.blank?

    /\b(?:#{terms.map { Regexp.escape(_1) }.join("|")})[a-z]*/i
  end

  # The `size` consecutive lines with the most distinct term matches (then
  # most matches overall); the first lines when nothing matches.
  def self.excerpt(lines, terms, size: 6)
    return lines if lines.size <= size

    return lines.first(size) if terms.blank?

    patterns = terms.map { /\b#{Regexp.escape(_1)}/i }
    # For each line, the indexes of the terms it contains.
    found = lines.map { |line| "#{line.speaker} #{line.text}".then { |s| patterns.each_index.select { patterns[_1].match?(s) } } }
    best = (0..lines.size - size).max_by do |start|
      window = found[start, size]
      [window.flatten.uniq.size, window.sum(&:size), -start]
    end
    lines[best, size]
  end
end
