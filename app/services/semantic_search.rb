# Finds the episodes that best match a free-text description.
#
#   1. The query is embedded exactly as typed (one API call, cached).
#   2. pgvector finds its nearest transcript chunks (scenes), and separately
#      the episodes whose summaries (from TVMaze) are closest, optionally in
#      one series.
#   3. Each episode gets a rank in both lists, and they are combined with
#      reciprocal rank fusion: summaries match descriptions of the plot ("Picard
#      lives another life"), scenes match what is said or done in one moment.
#      Each episode comes with its best-matching scenes.
#
# SearchQueryPlanner isn't part of the search: the results page only offers
# its tidied query as a suggestion.
#
# Without an API key nothing can be embedded, so callers should rescue
# OpenaiApi::Error.
class SemanticSearch
  CHUNKS = 40
  SUMMARIES = 40       # episodes ranked by summary
  MAX_EPISODES = 8
  SCENES_PER_EPISODE = 3
  # Reciprocal rank fusion: score = SUMMARY_WEIGHT / (RRF_K + summary rank)
  # + 1 / (RRF_K + scene rank), where an episode missing from a list counts as
  # one past its end. Tuned on `bin/rails search:eval`.
  SUMMARY_WEIGHT = 2.0
  RRF_K = 20

  # One episode in the results. `rank` is 1-based; `scenes` are chunks, best
  # first, each responding to #neighbor_distance; `score` is the cosine
  # similarity of the episode's closest chunk, and `summary_score` that of its
  # summary (nil if it has none, or wasn't among the closest SUMMARIES).
  Hit = Data.define(:rank, :episode, :scenes, :score, :summary_score) do
    def initialize(rank:, episode:, scenes:, score:, summary_score: nil) = super
  end

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

  # Ranks episodes by their closest scene (the nearest chunks, grouped by
  # episode; they come back closest first, so each episode's scenes stay in
  # that order) and by their summary, then fuses the two ranks.
  def rank_episodes(vector, filters)
    scenes = EpisodeChunk.nearest(vector, limit: CHUNKS, filters: filters).group_by(&:episode_text_id)
    summaries = nearest_summaries(vector, filters)
    scene_rank = scenes.keys.each_with_index.to_h { |id, i| [id, i + 1] }
    summary_rank = summaries.keys.each_with_index.to_h { |id, i| [id, i + 1] }

    ranked = (scene_rank.keys | summary_rank.keys).sort_by do |id|
      fused = SUMMARY_WEIGHT / (RRF_K + summary_rank.fetch(id, SUMMARIES + 1)) +
              1.0 / (RRF_K + scene_rank.fetch(id, CHUNKS + 1))
      [-fused, id]
    end.first(MAX_EPISODES)

    # Episodes found by their summary alone have no chunk among the nearest.
    scenes.merge!(closest_scenes(vector, ranked - scenes.keys))
    ranked.select! { scenes[_1] } # a summary but no embedded scenes yet
    return [] if ranked.empty?

    episodes = EpisodeText.without_text.where(id: ranked).index_by(&:id)
    ranked.each_with_index.map do |id, i|
      list = scenes[id].first(SCENES_PER_EPISODE)
      Hit.new(rank: i + 1, episode: episodes.fetch(id), scenes: list,
              score: 1 - list.first.neighbor_distance, summary_score: summaries[id])
    end
  end

  # { episode id => summary similarity }, closest first. ~700 rows, so an
  # exact scan (there is no index).
  def nearest_summaries(vector, filters)
    scope = EpisodeText.where.not(summary_embedding: nil)
    scope = scope.where(series: filters[:series]) if filters[:series]
    scope.select(:id).nearest_neighbors(:summary_embedding, vector, distance: "cosine").limit(SUMMARIES)
      .to_h { [_1.id, 1 - _1.neighbor_distance] }
  end

  # { episode id => its SCENES_PER_EPISODE closest chunks, closest first },
  # computed exactly over those episodes' chunks rather than through the
  # vector index.
  def closest_scenes(vector, episode_ids)
    return {} if episode_ids.empty?

    distance = "embedding <=> #{EpisodeChunk.connection.quote("[#{vector.join(',')}]")}::vector"
    inner = EpisodeChunk.where(episode_text_id: episode_ids)
      .select(*EpisodeChunk::HIT_COLUMNS, "#{distance} AS neighbor_distance",
              "row_number() OVER (PARTITION BY episode_text_id ORDER BY #{distance}) AS place")
    EpisodeChunk.from(inner, :episode_chunks).where("place <= ?", SCENES_PER_EPISODE)
      .order(:neighbor_distance).group_by(&:episode_text_id)
  end

  def time(name)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
  ensure
    @timings[name] = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
  end
end
