class EpisodeChunk < ApplicationRecord
  belongs_to :episode_text

  has_neighbors :embedding

  # Characters per chunk (~500 tokens) and overlap between neighbouring chunks.
  CHUNK_SIZE = 2000
  CHUNK_OVERLAP = 200

  # Returns the closest chunks to a free-text query, nearest first, as an Array.
  # Each result responds to #neighbor_distance (cosine distance: 0 = identical).
  #
  # filters: series:, season:, episode_number:, title: (all optional). They are
  # applied with bound parameters only, so they're safe to take from user or
  # model input.
  def self.semantic_search(query, limit: 10, filters: {})
    embedding = OpenaiEmbeddings.embed(query).first
    scope = filtered(filters)
      .nearest_neighbors(:embedding, embedding, distance: "cosine")
      .preload(:episode_text)
      .limit(limit)

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
