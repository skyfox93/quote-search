# Finds the episodes that best match a free-text description.
#
#   1. The query is embedded exactly as typed (one API call, cached) and
#      pgvector finds its nearest transcript chunks, optionally in one series.
#   2. Episodes are ranked by the average similarity of their top three
#      chunks, each with its best-matching scenes.
#
# SearchQueryPlanner isn't part of the search: the results page only offers
# its tidied query as a suggestion.
#
# Without an API key nothing can be embedded, so callers should rescue
# OpenaiApi::Error.
class SemanticSearch
  CHUNKS = 40
  MAX_EPISODES = 8
  SCENES_PER_EPISODE = 3
  SCORED_CHUNKS = 3 # an episode's score averages its closest this-many chunks

  # One episode in the results. `rank` is 1-based; `scenes` are chunks, best
  # first, each responding to #neighbor_distance; `score` is the average cosine
  # similarity of the episode's top SCORED_CHUNKS retrieved chunks.
  Hit = Data.define(:rank, :episode, :scenes, :score)

  # relaxed_filters: the series filter matched nothing (that series has no
  # embeddings yet), so these hits are from every series instead.
  Result = Data.define(:query, :hits, :filters, :relaxed_filters, :timings) do
    def series_filter = filters[:series]
  end

  # series: a code from EpisodeText::SERIES to search only that series, or nil.
  def self.call(query, series: nil)
    new(query, series: series).call
  end

  def initialize(query, series: nil)
    @query = query.to_s.squish
    @series = series.presence
    @timings = {}
  end

  def call
    filters = { series: @series }.compact
    vector = time(:embed) { OpenaiEmbeddings.embed_cached([@query]).first }
    hits = time(:db) { rank_episodes(vector, filters) }
    relaxed = hits.empty? && filters.any?
    hits = time(:db_unfiltered) { rank_episodes(vector, {}) } if relaxed

    Rails.logger.info("[semantic search] #{@timings.map { |k, v| "#{k} #{v}ms" }.join(", ")} for #{@query.inspect}")
    Result.new(query: @query, hits: hits, filters: filters, relaxed_filters: relaxed, timings: @timings)
  end

  # Series that have embeddings, e.g. ["TNG"]. Cached briefly: it only
  # changes when someone runs `bin/rails seed_embedding`.
  def self.indexed_series
    Rails.cache.fetch("semantic_search/indexed_series", expires_in: 10.minutes) do
      EpisodeText.where(id: EpisodeChunk.select(:episode_text_id)).distinct.pluck(:series)
    end
  end

  private

  # Groups the nearest chunks by episode and scores each episode by the average
  # similarity of its top SCORED_CHUNKS chunks, counting missing ones as 0, so
  # one close match on its own can't put an episode first. The chunks come
  # back closest first, so each episode's scenes stay in that order.
  def rank_episodes(vector, filters)
    chunks = EpisodeChunk.nearest(vector, limit: CHUNKS, filters: filters)
    ranked = chunks.group_by(&:episode_text_id)
      .map { |id, list| [id, list, list.first(SCORED_CHUNKS).sum { 1 - _1.neighbor_distance } / SCORED_CHUNKS] }
      .sort_by { |id, _list, score| [-score, id] }
      .first(MAX_EPISODES)
    return [] if ranked.empty?

    episodes = EpisodeText.without_text.where(id: ranked.map(&:first)).index_by(&:id)
    ranked.each_with_index.map do |(id, list, score), i|
      Hit.new(rank: i + 1, episode: episodes.fetch(id), scenes: list.first(SCENES_PER_EPISODE), score: score)
    end
  end

  def time(name)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
  ensure
    @timings[name] = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
  end
end
