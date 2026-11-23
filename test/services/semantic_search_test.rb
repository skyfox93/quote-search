require "test_helper"

# Runs the real vector queries against pgvector; only the OpenAI calls
# (planner and embeddings) are stubbed.
class SemanticSearchTest < ActiveSupport::TestCase
  Plan = SearchQueryPlanner::Plan
  Guess = SearchQueryPlanner::Guess

  def vec(weights)
    Array.new(OpenaiEmbeddings::DIMENSIONS, 0.0).tap { |v| weights.each { |i, w| v[i] = w } }
  end

  setup do
    Rails.cache.clear
    @a = episode("Alpha", vec(0 => 1.0))
    @b = episode("Beta", vec(1 => 1.0))
    @c = episode("Gamma", vec(2 => 1.0))
    @unembedded = EpisodeText.create!(series: "TNG", episode: "episode 904", title: "Delta", text: "x")
  end

  def episode(title, embedding)
    EpisodeText.create!(series: "TNG", episode: "episode #{900 + title.length}#{title[0]}", title: title,
                        text: "#{title.upcase}: hello").tap do |ep|
      ep.episode_chunks.create!(position: 0, content: "#{title.upcase}: hello", embedding: embedding)
    end
  end

  # Stubs the planner and the embeddings: the planner's passage embeds as
  # `passage`, the user's words as `raw`.
  def search(query = "q", passage:, raw:, series: nil, guesses: [], **opts)
    plan = Plan.new(query: "passage", keywords: nil, series: series, guesses: guesses, rewritten: true)
    vectors = { "passage" => passage, query => raw }
    stub_method(SearchQueryPlanner, :plan, plan) do
      stub_method(OpenaiEmbeddings, :embed_cached, ->(texts) { texts.map { vectors.fetch(_1) } }) do
        SemanticSearch.call(query, **opts)
      end
    end
  end

  test "ranks episodes by both vectors, with scenes and similarity" do
    result = search(passage: vec(0 => 1.0, 1 => 0.5), raw: vec(0 => 1.0, 1 => 0.2))

    assert_equal [@a, @b, @c].map(&:id), result.hits.map { _1.episode.id }.first(3)
    assert_equal [1, 2, 3], result.hits.first(3).map(&:rank)
    # Best of the two vectors' cosine similarities to Alpha's chunk (1, 0).
    assert_in_delta 1 / Math.sqrt(1.04), result.hits.first.similarity, 0.001
    assert_equal "ALPHA: hello", result.hits.first.scenes.first.content
    assert_nil result.hits.first.episode.attributes["text"], "lists shouldn't load full transcripts"
  end

  test "a guessed episode is ranked up" do
    result = search(passage: vec(0 => 1.0, 1 => 0.5), raw: vec(0 => 1.0, 1 => 0.2),
                    guesses: [Guess.new(series: "TNG", title: "Beta")])

    assert_equal @b.id, result.hits.first.episode.id
    assert result.hits.first.guessed
  end

  test "guessed episodes without embeddings are left out" do
    result = search(passage: vec(0 => 1.0), raw: vec(0 => 1.0), guesses: [Guess.new(series: "TNG", title: "Delta")])
    assert_not_includes result.hits.map { _1.episode.id }, @unembedded.id
  end

  test "falls back to all series when the filter matches nothing" do
    result = search(passage: vec(0 => 1.0), raw: vec(0 => 1.0), series: "DS9")

    assert result.relaxed_filters
    assert_equal "DS9", result.series_filter
    assert_equal @a.id, result.hits.first.episode.id
  end

  test "use_filters: false ignores the plan's series" do
    result = search(passage: vec(0 => 1.0), raw: vec(0 => 1.0), series: "DS9", use_filters: false)

    assert_not result.relaxed_filters
    assert_nil result.series_filter
    assert result.hits.any?
  end

  test "nearest_in_episodes returns each episode's closest chunks" do
    @a.episode_chunks.create!(position: 1, content: "ALPHA: later", embedding: vec(0 => 0.5, 3 => 1.0))
    found = EpisodeChunk.nearest_in_episodes(vec(0 => 1.0), [@a.id, @b.id], per: 1)

    assert_equal ["ALPHA: hello"], found[@a.id].map(&:content)
    assert_equal ["BETA: hello"], found[@b.id].map(&:content)
    assert_in_delta 0.0, found[@a.id].first.neighbor_distance, 0.001
  end
end
