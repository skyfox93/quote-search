class EpisodeChunk < ApplicationRecord
  belongs_to :episode_text

  has_neighbors :embedding

  # Characters per chunk (~500 tokens) and overlap between neighbouring chunks.
  CHUNK_SIZE = 2000
  CHUNK_OVERLAP = 200

  # Returns the closest chunks to a free-text query, nearest first.
  # Each result responds to #neighbor_distance (cosine distance: 0 = identical).
  def self.semantic_search(query, limit: 10)
    embedding = OpenaiEmbeddings.embed(query).first
    nearest_neighbors(:embedding, embedding, distance: "cosine")
      .includes(:episode_text)
      .limit(limit)
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
