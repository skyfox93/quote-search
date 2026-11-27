require "test_helper"

# Runs the real vector queries against pgvector; only the embedding call is
# stubbed.
class SemanticSearchTest < ActiveSupport::TestCase
  def vec(weights)
    Array.new(OpenaiEmbeddings::DIMENSIONS, 0.0).tap { |v| weights.each { |i, w| v[i] = w } }
  end

  setup do
    Rails.cache.clear
    @a = episode("Alpha", vec(0 => 1.0))
    @b = episode("Beta", vec(1 => 1.0))
    @c = episode("Gamma", vec(2 => 1.0))
  end

  def episode(title, embedding)
    EpisodeText.create!(series: "TNG", episode: "episode #{900 + title.length}#{title[0]}", title: title,
                        text: "#{title.upcase}: hello").tap do |ep|
      ep.episode_chunks.create!(position: 0, content: "#{title.upcase}: hello", embedding: embedding)
    end
  end

  # Stubs the embedding of the query, checking it's embedded as typed (only
  # squished), and that the planner isn't asked.
  def search(query = "  in what episode   does Geordi become an assassin ", vector:, **opts)
    planner = ->(*) { flunk "the search shouldn't use the planner" }
    stub_method(SearchQueryPlanner, :plan, planner) do
      stub_method(OpenaiEmbeddings, :embed_cached, ->(texts) { assert_equal [query.squish], texts; [vector] }) do
        SemanticSearch.call(query, **opts)
      end
    end
  end

  test "ranks episodes by score, with scenes" do
    result = search(vector: vec(0 => 1.0, 1 => 0.5))

    assert_equal [@a, @b, @c].map(&:id), result.hits.map { _1.episode.id }.first(3)
    assert_equal [1, 2, 3], result.hits.first(3).map(&:rank)
    # An episode's score is its closest chunk's similarity.
    assert_in_delta 1 / Math.sqrt(1.25), result.hits.first.score, 0.001
    assert_equal "ALPHA: hello", result.hits.first.scenes.first.content
    assert_nil result.hits.first.episode.attributes["text"], "lists shouldn't load full transcripts"
  end

  test "an episode's scenes are its matching chunks, closest first" do
    @b.episode_chunks.create!(position: 1, content: "BETA: later", embedding: vec(0 => 1.0, 1 => 1.0))
    result = search(vector: vec(0 => 1.0))

    assert_equal [@a.id, @b.id], result.hits.first(2).map { _1.episode.id }
    assert_equal ["BETA: later", "BETA: hello"], result.hits.second.scenes.map(&:content)
  end

  test "scores an episode by its closest chunk, however many others match" do
    # Beta has one chunk equal to the query; Gamma has two at ~0.96. Beta's
    # one close match wins, and Alpha (~1.0) comes between them.
    query = vec(0 => 1.0, 3 => 0.01)
    @b.episode_chunks.create!(position: 1, content: "BETA: close", embedding: query)
    2.times { |i| @c.episode_chunks.create!(position: i + 1, content: "GAMMA: near", embedding: vec(0 => 1.0, 4 => 0.3)) }
    result = search(vector: query)

    assert_equal [@b, @a, @c].map(&:id), result.hits.map { _1.episode.id }
    assert_in_delta 1.0, result.hits.first.score, 0.001
    assert_equal "BETA: close", result.hits.first.scenes.first.content
  end

  test "falls back to all series when the filter matches nothing" do
    result = search(vector: vec(0 => 1.0), series: "DS9")

    assert result.relaxed_filters
    assert_equal "DS9", result.series_filter
    assert_equal @a.id, result.hits.first.episode.id
  end

  test "a series filter keeps other series out" do
    other = EpisodeText.create!(series: "DS9", episode: "episode 999", title: "Delta", text: "DELTA: hello")
    other.episode_chunks.create!(position: 0, content: "DELTA: hello", embedding: vec(0 => 1.0))
    result = search(vector: vec(0 => 1.0), series: "TNG")

    assert_not result.relaxed_filters
    assert_equal "TNG", result.series_filter
    assert_not_includes result.hits.map { _1.episode.id }, other.id
    assert_includes search(vector: vec(0 => 1.0)).hits.map { _1.episode.id }, other.id
  end
end
