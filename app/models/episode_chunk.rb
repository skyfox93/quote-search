class EpisodeChunk < ApplicationRecord
  belongs_to :episode_text

  has_neighbors :embedding

  # Characters per chunk (~500 tokens) and overlap between neighbouring chunks.
  CHUNK_SIZE = 2000
  CHUNK_OVERLAP = 200

  # Columns needed to show a hit. Leaves out the embedding itself, which is
  # ~20KB of text per row for Postgres to send and Ruby to parse.
  HIT_COLUMNS = %i[id episode_text_id position content].freeze

  # The closest chunks to each vector, nearest first: one Array per vector.
  # Each row responds to #neighbor_distance (cosine distance: 0 = identical).
  #
  # filters: series:, season:, episode_number:, title: (all optional). They are
  # applied with bound parameters only, so they're safe to take from user or
  # model input.
  def self.nearest(vectors, limit: 40, filters: {})
    scopes = vectors.map do |vector|
      filtered(filters).select(*HIT_COLUMNS).nearest_neighbors(:embedding, vector, distance: "cosine").limit(limit)
    end

    transaction do
      # With a WHERE clause, a plain HNSW scan can return fewer than `limit`
      # rows. Iterative scans (pgvector 0.8+) keep searching until enough match.
      # relaxed_order can return rows slightly out of order, so re-sort them.
      connection.execute("SET LOCAL hnsw.iterative_scan = relaxed_order") if filters.compact.any?
      scopes.map { |scope| scope.to_a.sort_by(&:neighbor_distance) }
    end
  end

  # The `per` closest chunks to `vector` in each of the given episodes, as
  # { episode_text_id => [chunks, nearest first] }. Exact (no index): each
  # episode has only a few dozen chunks.
  def self.nearest_in_episodes(vector, episode_ids, per: 3)
    return {} if episode_ids.empty?

    literal = "[#{vector.map { Float(_1) }.join(",")}]"
    ranked = select(*HIT_COLUMNS)
      .select(sanitize_sql_array(["embedding <=> ?::vector AS neighbor_distance", literal]))
      .select(sanitize_sql_array(["row_number() OVER (PARTITION BY episode_text_id ORDER BY embedding <=> ?::vector) AS rank_in_episode", literal]))
      .where(episode_text_id: episode_ids)
      .where.not(embedding: nil)

    from(ranked, :episode_chunks).where("rank_in_episode <= ?", per).order(:neighbor_distance)
      .to_a.group_by(&:episode_text_id)
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

  # Splits text into overlapping chunks, breaking on line boundaries where possible.
  def self.split(text)
    chunks = []
    start = 0
    text = text.to_s
    while start < text.length
      finish = [start + CHUNK_SIZE, text.length].min
      if finish < text.length
        newline = text.rindex("\n", finish)
        finish = newline if newline && newline > start + CHUNK_SIZE / 2
      end
      chunk = text[start...finish].strip
      chunks << chunk unless chunk.empty?
      break if finish >= text.length
      start = finish - CHUNK_OVERLAP
    end
    chunks
  end
end
