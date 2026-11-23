# Standardizes the speaker names parsed from the transcripts, which come in
# many shapes for the same person:
#
#   "PICARD [OC]", "DUKAT [on monitor]"   -> "PICARD", "DUKAT" (note: "OC", "on monitor")
#   "TANIS (telepathically)", "ODO {OC]"  -> "TANIS", "ODO"
#   "THARN [on viewscreen", "PARIS:"      -> "THARN", "PARIS"
#   "EMH2", "WEYOUN7", "T'POL1"           -> "EMH 2", "WEYOUN 7", "T'POL 1" (numbered
#                                            people stay distinct: RIKER 2 is Thomas Riker)
#
# The import also ran some lines together, leaving text in the name. Two shapes:
#   (a) the real speaker's name is glued on the end:
#       "KES: No. (She looks up.)KES" -> "KES", "...don't stopPARIS" -> "PARIS"
#   (b) a colon inside the line split it early, so the speaker is the prefix:
#       "DATA: Computer" (line: "request all biographical information...") -> "DATA"
#
# ALIASES then fixes misspellings, per series.
module CharacterName
  # note: how the line was delivered ("OC", "on viewscreen"), if the raw name said.
  Result = Data.define(:name, :note)

  # Misspellings, per series. Each was a rare name one letter away from a
  # common one that speaks in the same episode (checked in the data), except
  # TOMOLAK, a known misspelling of the recurring Romulan commander.
  ALIASES = {
    "ENT" => { "ARC HER" => "ARCHER", "ARCHEHR" => "ARCHER", "HOSIHI" => "HOSHI", "MESTRA" => "MESTRAL",
               "SKALARR" => "SKALAAR", "SONG" => "SOONG" },
    "TNG" => { "JEAN LUC" => "JEAN-LUC", "PIKER" => "RIKER", "RATA" => "DATA", "TOMOLAK" => "TOMALAK", "WORD" => "WORF" },
    "TOS" => { "NUDD" => "MUDD", "SCOT" => "SCOTT" },
    "VOY" => { "CHAOTAY" => "CHAKOTAY", "GOTATA-RETZ" => "GOTANA-RETZ", "HAWKINS" => "HARKINS", "QATATI" => "QATAI" }
  }.freeze

  NAME = %r{[A-Z][A-Z0-9'.\-/ ]*}
  TAG = /\[[^\]]*\]?|\([^)]*\)?/
  # Characters that can end text that ran into a name.
  DELIMITER = /[a-z)\].:!?,;#"]/

  def self.standardize(raw, series: nil)
    text = raw.to_s.tr("{}", "[]").gsub(/<br\s*\/?>/i, " ").gsub(/\s+/, " ").strip
    return Result.new(name: text, note: nil) if text.empty?

    text = speaker_text(text)
    notes = text.scan(TAG).map { _1.delete("[]()").strip }.reject(&:empty?)
    base = text.gsub(TAG, " ").delete("[]()")
    base = base.gsub(/\s+/, " ").strip.sub(/\A[^A-Za-z0-9]+/, "").sub(/[^A-Za-z0-9']+\z/, "").upcase
    base = base.sub(/(?<=[A-Z'])(\d+)\z/, ' \1') # EMH2 -> EMH 2
    base = ALIASES.fetch(series, {}).fetch(base, base)

    Result.new(name: base.presence || raw.to_s.strip, note: notes.join("; ").presence)
  end

  # The part of the raw text that names the speaker (with any [tag]).
  def self.speaker_text(text)
    return text if text.match?(/\A#{NAME}\s*(?:#{TAG}\s*)*\z/o) # already clean

    if (m = text.match(/(?:#{DELIMITER}|\A)\s*(#{NAME}\s*(?:#{TAG})?)\s*\z/o)) && m[1].match?(/[A-Z]{2}|\A[A-Z]\b/)
      m[1] # (a) name glued on the end
    elsif (m = text.match(/\A(#{NAME}\s*(?:#{TAG})?)\s*:/o))
      m[1] # (b) "NAME: text"
    elsif text.match?(/[a-z]{3}/)
      "SCENE" # stage directions with no speaker, as the import labels them elsewhere
    else
      text
    end
  end
end
