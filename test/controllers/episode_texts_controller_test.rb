require "test_helper"

class EpisodeTextsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @episode = EpisodeText.create!(series: "TNG", episode: "episode 950", title: "The Mind's Eye", season: 4, episode_number: 24,
                                   text: "LAFORGE: Hello.\nPICARD: <script>alert(1)</script>\nDATA: Romulan signals.\nTROI: Goodbye.")
    @chunk = @episode.episode_chunks.create!(position: 0, content: @episode.text)
  end

  test "index renders the search page without searching" do
    get episode_texts_path(query: "Geordi assassin")
    assert_response :success
    assert_select "turbo-frame#search-results[src*='query=Geordi+assassin']"
  end

  test "results explain when no API key is configured" do
    with_env("OPENAI_API_KEY" => nil) do
      get results_episode_texts_path(query: "Geordi assassin")
    end
    assert_response :success
    assert_select ".notice--error", /OPENAI_API_KEY/
  end

  test "results render hits and the AI answer placeholder" do
    hit = SemanticSearch::Hit.new(rank: 1, episode: @episode, scenes: [@chunk.tap { _1.define_singleton_method(:neighbor_distance) { 0.2 } }], guessed: false)
    plan = SearchQueryPlanner::Plan.new(query: "q", keywords: "Romulan", series: "TNG", guesses: [], rewritten: true)
    result = SemanticSearch::Result.new(query: "q", plan: plan, hits: [hit], filters: { series: "TNG" }, relaxed_filters: false, timings: {})

    stub_method(SemanticSearch, :call, result) do
      get results_episode_texts_path(query: "Geordi assassin")
    end

    assert_response :success
    assert_select "[data-controller=summary][data-summary-count-value='1']"
    assert_select "#result-1 .result__title", "The Mind's Eye"
    assert_select "#result-1 mark", "Romulan"
    assert_select ".filter-chip", /The Next Generation/
    assert_no_match(/<script>alert/, response.body)
  end

  test "show escapes the transcript and highlights the linked lines" do
    get episode_text_path(@episode, chunk: @chunk.id, line: 1, lines: 2)

    assert_response :success
    assert_no_match(/<script>alert/, response.body)
    assert_select ".line--match", 2
    assert_select "#match", /alert\(1\)/
  end

  test "show ignores chunks from other episodes" do
    other = EpisodeText.create!(series: "TNG", episode: "episode 951", title: "Other", text: "A: b")
    get episode_text_path(other, chunk: @chunk.id, line: 0, lines: 2)

    assert_response :success
    assert_select ".line--match", 0
  end
end
