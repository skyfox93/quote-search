# Splits one raw transcript (db/all_scripts_raw.json) into speeches and stage
# text.
#
# The raw scripts are hard-wrapped at ~70 characters, and every speech starts
# at the beginning of a line:
#
#   PICARD: Crewman? What is going on?
#   Q: Welcome, Picard, to shuttlecraft six.
#   (A wave of the hand and the uniform is clean
#   again)
#   [Corridor]
#
# So a block starts at "NAME:" at the start of a line (any length of name, so
# "Q" counts, ending at the first colon), and continues over wrapped lines.
# Locations ("[Bridge]") and stage directions starting a line after a finished
# sentence become SCENE blocks, as do the header and narration.
class TranscriptParser
  SCENE = "SCENE".freeze

  # character_raw: the speaker as written ("PICARD [OC]"), or nil for scene text.
  Block = Data.define(:index, :character_raw, :text) do
    def scene? = character_raw.nil?
    # How the line reads in the transcript.
    def to_s = scene? ? text : "#{character_raw}: #{text}"
  end

  # "PICARD:", "Q:", "DR. CRUSHER:", "PICARD [OC]:", "TANIS (telepathically):",
  # "WEYOUN 7 [on monitor]:" at the start of a line.
  SPEAKER = /\A([A-Z][A-Z0-9'.\-\/ ]{0,40}?(?:\s*[\[{(][^\]})\n]{0,40}[\]})])?)\s*:(?:\s+(.*)|\s*)\z/
  # A speaker run into the end of a stage direction: "...leaves.)KES: Neelix!"
  RUN_ON = /(?<=[)\]])[ \t]*(?=[A-Z][A-Z0-9'\-]*(?:\s*\[[^\]\n]*\])?:\s)/
  # A delivery tag wrapped onto the next line: "JANEWAY\n[OC]: text".
  WRAPPED_TAG = /^[ \t]*([A-Z][A-Z0-9'.\-\/ ]{0,40})[ \t]*\n[ \t]*([\[{(][^\]})\n]{0,40}[\]})][ \t]*:)/
  FOOTER = /\s*<\s*Back\s+to\s+the\s+episode\s+listing.*\z/m
  SENTENCE_END = /[.!?)\]"'\-]\z/

  def self.parse(raw)
    new(raw).blocks
  end

  # Rows for Dialogue.insert_all: one per block, with the speaker
  # standardized (see CharacterName) and the name as written kept.
  def dialogue_rows(series:, episode:)
    blocks.map do |block|
      name = CharacterName.standardize(block.character_raw || SCENE, series: series)
      { series: series, episode: episode, index: block.index, line: block.text,
        character: block.scene? ? SCENE : name.name, character_raw: block.character_raw || SCENE, delivery: name.note }
    end
  end

  def initialize(raw)
    @raw = raw.to_s
  end

  def blocks
    @blocks ||= build
  end

  # The transcript rebuilt one block per line ("NAME: speech").
  def text
    blocks.map(&:to_s).join("\n")
  end

  private

  def build
    text = @raw.gsub(/\r\n?/, "\n").tr("\u00A0\u2007\u202F", "   ").sub(FOOTER, "")
    text = text.gsub(/<br\s*\/?>/i, "\n").gsub(WRAPPED_TAG, '\\1 \\2').gsub(RUN_ON, "\n")
    blocks = []
    speaker = nil   # current block's speaker (nil = scene text)
    lines = nil     # current block's lines, nil when no block is open

    flush = lambda do
      body = lines&.join(" ")&.squish
      blocks << [speaker, body] if body.present? || speaker
      lines = nil
    end

    text.each_line(chomp: true) do |line|
      stripped = line.strip

      if stripped.empty?
        flush.() if lines && speaker # a blank line ends a speech; scene text can span paragraphs
      elsif (m = stripped.match(SPEAKER))
        flush.() if lines
        speaker = m[1].strip
        lines = [m[2].to_s]
      elsif stripped.match?(/\A\[[^\]]*\]\z/) # a location on its own line
        flush.() if lines
        speaker = nil
        lines = [stripped]
        flush.()
      elsif stripped.start_with?("(", "{") && (lines.nil? || (speaker && lines.last.to_s.strip.match?(SENTENCE_END)))
        flush.() if lines # a stage direction after a finished speech
        speaker = nil
        lines = [stripped]
      elsif lines
        lines << stripped
      else
        speaker = nil
        lines = [stripped]
      end
    end
    flush.() if lines

    blocks.each_with_index.map { |(name, body), i| Block.new(index: i, character_raw: name, text: body.to_s) }
  end
end
