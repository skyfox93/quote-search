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
    assert_select "turbo-frame#search-suggestion[src*='query=Geordi+assassin']"
  end

  test "index keeps a series filter from the URL, and ignores unknown series" do
    get episode_texts_path(query: "Geordi assassin", series: "TNG")
    assert_select "turbo-frame#search-results[src*='series=TNG']"
    assert_select "input[type=hidden][name=series][value=TNG]"

    get episode_texts_path(query: "Geordi assassin", series: "'; DROP")
    assert_select "turbo-frame#search-results[src*='series']", 0
  end

  test "results explain when no API key is configured" do
    with_env("OPENAI_API_KEY" => nil) do
      get results_episode_texts_path(query: "Geordi assassin")
    end
    assert_response :success
    assert_select ".notice--error", /OPENAI_API_KEY/
  end

  test "results render hits and the AI summary placeholder" do
    hit = SemanticSearch::Hit.new(rank: 1, episode: @episode, scenes: [@chunk.tap { _1.define_singleton_method(:neighbor_distance) { 0.2 } }], score: 0.8)
    result = SemanticSearch::Result.new(query: "Romulan", hits: [hit], filters: { series: "TNG" }, relaxed_filters: false, timings: {})
    called_with = nil

    stub_method(SemanticSearch, :call, ->(query, **opts) { called_with = [query, opts]; result }) do
      get results_episode_texts_path(query: "Romulan", series: "TNG")
    end

    assert_response :success
    assert_equal ["Romulan", { series: "TNG" }], called_with
    assert_select "[data-controller=summary][data-summary-count-value='1']"
    assert_select "#result-1 .result__title", "The Mind's Eye"
    assert_select "#result-1 .result__score", /0\.80/
    assert_select "#result-1 mark", "Romulan"
    assert_select ".filter-chip", /The Next Generation/
    assert_no_match(/<script>alert/, response.body)
  end

  test "suggestion offers the planner's tidier query as a link" do
    plan = SearchQueryPlanner::Plan.new(query: "Geordi become an assassin", series: "TNG", rewritten: true)
    with_env("OPENAI_API_KEY" => "test-key") do
      stub_method(SearchQueryPlanner, :plan, plan) do
        get suggestion_episode_texts_path(query: "in what episode of TNG does Geordi become an assassin")
      end
    end

    assert_response :success
    assert_select "turbo-frame#search-suggestion .search-suggestion a[href=?]",
                  episode_texts_path(query: "Geordi become an assassin", series: "TNG"), "Geordi become an assassin"
    assert_select ".search-suggestion", /in Star Trek: The Next Generation/
  end

  test "suggestion is empty when the planner changes nothing" do
    plan = SearchQueryPlanner::Plan.new(query: "geordi assassin", series: nil, rewritten: true)
    with_env("OPENAI_API_KEY" => "test-key") do
      stub_method(SearchQueryPlanner, :plan, plan) do
        get suggestion_episode_texts_path(query: "Geordi assassin")
      end
    end

    assert_response :success
    assert_select "turbo-frame#search-suggestion"
    assert_select ".search-suggestion", 0
  end

  test "suggestion is empty when the planner fails" do
    with_env("OPENAI_API_KEY" => "test-key") do
      stub_method(SearchQueryPlanner, :plan, ->(*) { raise OpenaiApi::Error, "down" }) do
        get suggestion_episode_texts_path(query: "Geordi assassin")
      end
    end

    assert_response :success
    assert_select ".search-suggestion", 0
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
