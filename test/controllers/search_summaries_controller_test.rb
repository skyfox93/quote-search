require "test_helper"

class SearchSummariesControllerTest < ActionDispatch::IntegrationTest
  test "needs a query" do
    get search_summary_path
    assert_response :bad_request
  end

  test "is unavailable without an API key" do
    with_env("OPENAI_API_KEY" => nil) do
      get search_summary_path(query: "Geordi assassin")
    end
    assert_response :service_unavailable
  end

  test "streams the summarizer's text" do
    episode = EpisodeText.create!(series: "TNG", episode: "episode 960", title: "Darmok", text: "x")
    chunk = episode.episode_chunks.create!(position: 0, content: "DATHON: Darmok and Jalad at Tanagra.")
    chunk.define_singleton_method(:neighbor_distance) { 0.1 }
    hit = SemanticSearch::Hit.new(rank: 1, episode: episode, scenes: [chunk], guessed: false)
    plan = SearchQueryPlanner::Plan.new(query: "q", keywords: nil, series: nil, guesses: [], rewritten: true)
    result = SemanticSearch::Result.new(query: "q", plan: plan, hits: [hit], filters: {}, relaxed_filters: false, timings: {})

    sent = nil
    stream = lambda do |**kwargs, &block|
      sent = kwargs[:messages].last[:content]
      %w[It's Darmok [1].].each { block.call(_1 + " ") }
      "It's Darmok [1]."
    end

    with_env("OPENAI_API_KEY" => "test-key") do
      stub_method(SemanticSearch, :call, result) do
        stub_method(OpenaiApi, :stream_chat, stream) do
          get search_summary_path(query: "Picard and Dathon")
        end
      end
    end

    assert_response :success
    assert_equal "It's Darmok [1]. ", response.body
    assert_includes response.media_type, "text/plain"
    assert_includes sent, "Search: Picard and Dathon"
    assert_includes sent, "[1] Star Trek: The Next Generation, Darmok"
    assert_includes sent, "Darmok and Jalad at Tanagra"
  end
end
