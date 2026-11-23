# Finds the episodes that best match a free-text description.
#
#   1. SearchQueryPlanner rewrites the request as a few lines of plausible
#      script, guesses likely episodes, and picks out a series filter.
#   2. The rewritten passage and the user's own words are embedded (one API
#      call, cached) and each finds its nearest transcript chunks.
#   3. The two chunk rankings and the model's guesses are combined with
#      reciprocal rank fusion into one list of episodes, each with its
#      best-matching scenes.
#
# Without an API key nothing can be embedded, so callers should rescue
# OpenaiApi::Error.
class SemanticSearch
  CHUNKS_PER_VECTOR = 40
  MAX_EPISODES = 8
  SCENES_PER_EPISODE = 3
  RRF_K = 10 # small k: being first in a list counts for a lot more than being fifth

  # One episode in the results. `rank` is 1-based; `scenes` are chunks, best
  # first, each responding to #neighbor_distance.
  Hit = Data.define(:rank, :episode, :scenes, :guessed) do
    def similarity = 1 - scenes.first.neighbor_distance
  end

  # relaxed_filters: the plan's filters matched nothing, so these hits are
  # from every series instead.
  Result = Data.define(:query, :plan, :hits, :filters, :relaxed_filters, :timings) do
    def series_filter = filters[:series]
  end

  def self.call(query, use_filters: true)
    new(query, use_filters: use_filters).call
  end

  def initialize(query, use_filters: true)
    @query = query.to_s.squish
    @use_filters = use_filters
    @timings = {}
  end

  def call
    plan = time(:plan) { SearchQueryPlanner.plan(@query) }
    filters = @use_filters ? plan.filters : {}

    vectors = time(:embed) { OpenaiEmbeddings.embed_cached([plan.query, @query].uniq) }
    hits = time(:db) { rank_episodes(plan, vectors, filters) }
    relaxed = hits.empty? && filters.any?
    hits = time(:db_unfiltered) { rank_episodes(plan, vectors, {}) } if relaxed

    Rails.logger.info("[semantic search] #{@timings.map { |k, v| "#{k} #{v}ms" }.join(", ")} for #{@query.inspect}")
    Result.new(query: @query, plan: plan, hits: hits, filters: filters, relaxed_filters: relaxed, timings: @timings)
  end

  # Series that have embeddings, e.g. ["TNG"]. Cached briefly: it only
  # changes when someone runs `bin/rails seed_embedding`.
  def self.indexed_series
    Rails.cache.fetch("semantic_search/indexed_series", expires_in: 10.minutes) do
      EpisodeText.where(id: EpisodeChunk.select(:episode_text_id)).distinct.pluck(:series)
    end
  end

  private

  def rank_episodes(plan, vectors, filters)
    chunk_lists = EpisodeChunk.nearest(vectors, limit: CHUNKS_PER_VECTOR, filters: filters)
    guessed_ids = guessed_episode_ids(plan.guesses, filters)

    rankings = chunk_lists.map { |chunks| chunks.map(&:episode_text_id).uniq }
    rankings << guessed_ids
    # A few spare: guessed episodes that aren't embedded have no scenes to show.
    top_ids = fuse(rankings).first(MAX_EPISODES + SearchQueryPlanner::MAX_GUESSES)
    return [] if top_ids.empty?

    scenes = scenes_by_episode(chunk_lists.flatten)
    missing = top_ids.reject { scenes.key?(_1) }
    scenes.merge!(EpisodeChunk.nearest_in_episodes(vectors.first, missing, per: SCENES_PER_EPISODE)) if missing.any?

    episodes = EpisodeText.without_text.where(id: top_ids).index_by(&:id)
    top_ids.select { scenes[_1].present? && episodes[_1] }.first(MAX_EPISODES).each_with_index.map do |id, i|
      Hit.new(rank: i + 1, episode: episodes[id], scenes: scenes[id].first(SCENES_PER_EPISODE), guessed: guessed_ids.include?(id))
    end
  end

  # Guessed titles, matched within each guess's series (and the filter's, if
  # any), most likely first.
  def guessed_episode_ids(guesses, filters)
    guesses.select { filters[:series].nil? || _1.series == filters[:series] }
      .flat_map { EpisodeText.ids_for_titles([_1.title], series: _1.series) }.uniq
  end

  # Reciprocal rank fusion: each ranking adds 1 / (k + position) per episode.
  def fuse(rankings)
    scores = Hash.new(0.0)
    rankings.each { |ids| ids.each_with_index { |id, i| scores[id] += 1.0 / (RRF_K + i + 1) } }
    scores.sort_by { |id, score| [-score, id] }.map(&:first)
  end

  # { episode_id => chunks }, each chunk once (at its best distance), best first.
  def scenes_by_episode(chunks)
    chunks.group_by(&:episode_text_id).transform_values do |list|
      list.group_by(&:id).values.map { |same| same.min_by(&:neighbor_distance) }.sort_by(&:neighbor_distance)
    end
  end

  def time(name)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
  ensure
    @timings[name] = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
  end
end
