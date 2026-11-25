class EpisodeChunk < ApplicationRecord
  belongs_to :episode_text

  has_neighbors :embedding

  # Each chunk is one scene: scripts mark a scene change with its location
  # ("[Bridge]", "[Ten Forward]"), so a chunk starts at a location and runs
  # to the next one. A chunk is a coherent unit (one place, one set of
  # characters, one beat of plot), which is what people describe when they
  # search ("the scene where...").
  #
  # Scenes shorter than MIN_SCENE ("[Corridor] (Picard walks)") are merged
  # into the scene after them, since they say too little to embed alone.
  # Scenes longer than CHUNK_SIZE (~750 tokens; about 2% of TNG scenes) are
  # split into pieces of whole lines that repeat at least CHUNK_OVERLAP
  # characters of the piece before, so an exchange that straddles a cut
  # appears whole in at least one piece.
  CHUNK_SIZE = 3000
  CHUNK_OVERLAP = 200
  MIN_SCENE = 400

  # A location in brackets, starting a line or after a space, and not a
  # delivery tag before a colon ("PICARD [OC]: ...").
  LOCATION = /(?<![^\s])\[[^\]\n]{1,60}\](?!\s*:)/

  # Columns needed to show a hit. Leaves out the embedding itself, which is
  # ~20KB of text per row for Postgres to send and Ruby to parse.
  HIT_COLUMNS = %i[id episode_text_id position content].freeze

  # The closest chunks to `vector`, nearest first. Each row responds to
  # #neighbor_distance (cosine distance: 0 = identical).
  #
  # filters: series:, season:, episode_number:, title: (all optional). They are
  # applied with bound parameters only, so they are safe to take from user or
  # model input.
  def self.nearest(vector, limit: 40, filters: {})
    scope = filtered(filters).select(*HIT_COLUMNS).nearest_neighbors(:embedding, vector, distance: "cosine").limit(limit)
    transaction do
      # With a WHERE clause, a plain HNSW scan can return fewer than `limit`
      # rows. Iterative scans (pgvector 0.8+) keep searching until enough match.
      # relaxed_order can return rows slightly out of order, so re-sort them.
      connection.execute("SET LOCAL hnsw.iterative_scan = relaxed_order") if filters.compact.any?
      scope.to_a.sort_by(&:neighbor_distance)
    end
  end

  def self.filtered(filters)
    filters = filters.compact
    return all if filters.empty?

    episode_conditions = filters.slice(:series, :season, :episode_number)
    scope = joins(:episode_text)
    scope = scope.where(episode_texts: episode_conditions) if episode_conditions.any?
    if filters[:title].present?
      scope = scope.where("episode_texts.title ILIKE ?", "%#{sanitize_sql_like(filters[:title])}%")
    end
    scope
  end

  # Splits a transcript into chunks of one scene each (see CHUNK_SIZE), after
  # dropping the transcript site's header (title and airdate), which isn't
  # part of the script. Every chunk is an exact slice of the text, so the
  # episode page can find it again to highlight a result.
  def self.split(text)
    text = text.to_s.sub(ScriptText::HEADER, "")
    scene_ranges(text).filter_map { text[_1].strip.presence }.flat_map { split_lines(_1) }
  end

  # Where each scene starts and ends: cut at every location marker, so each
  # scene but the teaser starts with its location. A scene shorter than
  # MIN_SCENE runs on into the next one; a short last scene joins the one
  # before.
  def self.scene_ranges(text)
    short = ->(range) { text[range].strip.length < MIN_SCENE }
    starts = [0, *text.to_enum(:scan, LOCATION).map { Regexp.last_match.begin(0) }].uniq
    ranges = (starts + [text.length]).each_cons(2).each_with_object([]) do |(a, b), out|
      if out.any? && short.(out.last)
        out[-1] = out.last.begin...b
      else
        out << (a...b)
      end
    end
    ranges[-2..] = [ranges[-2].begin...ranges[-1].end] if ranges.size > 1 && short.(ranges.last)
    ranges
  end

  # Splits text longer than CHUNK_SIZE into overlapping pieces of whole lines
  # where possible: each piece ends at a line break, and the next starts at
  # the beginning of the line that holds its overlap point, so it repeats at
  # least CHUNK_OVERLAP characters of whole lines. Only a line longer than
  # half a chunk is cut mid-line.
  def self.split_lines(text)
    return [text] if text.length <= CHUNK_SIZE

    chunks = []
    start = 0
    while start < text.length
      finish = [start + CHUNK_SIZE, text.length].min
      if finish < text.length
        newline = text.rindex("\n", finish)
        finish = newline if newline && newline > start + CHUNK_SIZE / 2
      end
      chunk = text[start...finish].strip
      chunks << chunk unless chunk.empty?
      break if finish >= text.length

      overlap_from = finish - CHUNK_OVERLAP
      line_start = (text.rindex("\n", overlap_from) || -1) + 1
      start = line_start > start + CHUNK_SIZE / 2 ? line_start : overlap_from
    end
    chunks
  end
end
