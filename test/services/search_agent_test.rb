require "test_helper"

# The OpenAI Responses API is replaced by a script of canned outputs; the
# SQL really runs (through ReadonlySql) against the test database, reading
# the make_it_so dialogue fixture.
class SearchAgentTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
  end

  def tool_call(query, purpose = "Count lines", id: "call_1")
    { "type" => "function_call", "call_id" => id, "name" => "run_sql",
      "arguments" => { purpose: purpose, query: query }.to_json }
  end

  def scene_call(description, purpose = "Find the scene", id: "call_s")
  { "type" => "function_call", "call_id" => id, "name" => "search_scenes",
    "arguments" => { purpose: purpose, description: description }.to_json }
end

def answer_output(text)
    { "type" => "message", "content" => [{ "type" => "output_text", "text" => text }] }
  end

  # Returns the requests sent, so tests can inspect them.
  def with_responses(*outputs)
    requests = []
    post = lambda do |path, body, **|
      assert_equal "responses", path
      requests << body.deep_dup
      { "output" => outputs.shift || raise("no more canned responses") }
    end
    with_env("OPENAI_API_KEY" => "test-key") do
      stub_method(OpenaiApi, :post, post) { yield requests }
    end
  end

  test "runs the model's queries, feeds back the results, and answers" do
    with_responses(
      [{ "type" => "reasoning", "id" => "rs_1", "encrypted_content" => "abc" }, tool_call("SELECT count(*) AS n FROM dialogues WHERE episode = 'episode 970'")],
      [answer_output("Picard says it once.")]
    ) do |requests|
      events = SearchAgent.new("How often does Picard say make it so?").run

      assert_equal %i[sql answer], events.map(&:kind)
      assert_equal "Count lines", events.first.text
      assert_equal [[1]], events.first.result.rows
      assert_equal "Picard says it once.", events.last.text

      second = requests.last
      assert_equal false, second[:store]
      assert_includes second[:input].map { _1["type"] || _1[:type] }, "reasoning", "reasoning items are passed back"
      output = second[:input].find { (_1[:type] || _1["type"]) == "function_call_output" }
      assert_equal "call_1", output[:call_id]
      assert_equal 1, JSON.parse(output[:output])["rows"].first.first
    end
  end

  test "sends SQL errors back so the model can fix its query" do
    with_responses(
      [tool_call("DELETE FROM dialogues")],
      [tool_call("SELECT count(*) FROM dialogues WHERE episode = 'episode 970'", id: "call_2")],
      [answer_output("Done.")]
    ) do |requests|
      events = SearchAgent.new("q").run

      assert_not events.first.result.ok?
      assert events.second.result.ok?
      error_output = requests[1][:input].find { (_1[:type] || _1["type"]) == "function_call_output" }
      assert_match(/syntax error/, JSON.parse(error_output[:output])["error"])
    end
  end

  test "forces an answer on the last step" do
    calls = Array.new(SearchAgent::MAX_STEPS - 1) { |i| [tool_call("SELECT 1 AS x FROM dialogues LIMIT 1", id: "c#{i}")] }
    with_responses(*calls, [answer_output("Best guess.")]) do |requests|
      events = SearchAgent.new("q").run

      assert_equal "Best guess.", events.last.text
      assert_equal "none", requests.last[:tool_choice]
      assert_equal "auto", requests.first[:tool_choice]
    end
  end

  test "yields events as they happen and caches finished runs" do
    seen = []
    with_responses([tool_call("SELECT 1 AS x FROM dialogues LIMIT 1")], [answer_output("Answer.")]) do
      SearchAgent.new("cache me").run { seen << _1.kind }
    end
    assert_equal %i[sql answer], seen

    store = ActiveSupport::Cache::MemoryStore.new
    stub_method(Rails, :cache, store) do
      with_responses([answer_output("First.")]) { SearchAgent.new("cache me too").run }
      replay = SearchAgent.new("Cache me  TOO").run # same question, different spacing/case
      assert_equal "First.", replay.last.text
    end
  end

  test "reports API failures as an error event" do
    with_env("OPENAI_API_KEY" => "test-key") do
      stub_method(OpenaiApi, :post, ->(*, **) { raise OpenaiApi::Error, "boom" }) do
        events = SearchAgent.new("q").run
        assert_equal [:error], events.map(&:kind)
      end
    end
  end

  test "search_scenes runs the vector search on the model's description and returns episodes to follow up on" do
    episode = EpisodeText.create!(series: "TNG", episode: "episode 981", title: "Family", season: 4, episode_number: 2, text: "x")
    chunk = episode.episode_chunks.create!(position: 1, content: "PICARD: Robert, I...\nROBERT: Go on.")
    chunk.define_singleton_method(:neighbor_distance) { 0.4 }
    hit = SemanticSearch::Hit.new(rank: 1, episode: episode, scenes: [chunk], score: 0.6)
    result = SemanticSearch::Result.new(query: "Picard argues with his brother", hits: [hit], filters: {}, relaxed_filters: false, timings: { embed: 5, db: 7 })
    called_with = nil
    search = ->(query, **opts) { called_with = [query, opts]; result }
  
    stub_method(SemanticSearch, :call, search) do
      with_responses([scene_call("Picard argues with his brother")], [answer_output("Probably Family.")]) do |requests|
        events = SearchAgent.new("Which episode has Picard fighting his brother?").run
  
        assert_equal ["Picard argues with his brother", {}], called_with
        assert_equal %i[search answer], events.map(&:kind)
        assert_equal "Find the scene", events.first.text
        found = events.first.result.episodes.first
        assert_equal({ rank: 1, series: "TNG", episode: "episode 981", title: "Family", season: 4, episode_number: 2, similarity: 0.6 },
                     found.except(:scene))
        assert_equal "PICARD: Robert, I...\nROBERT: Go on.", found[:scene], "the whole chunk"
        assert_equal 12, events.first.result.ms
  
        output = requests.last[:input].find { (_1[:type] || _1["type"]) == "function_call_output" }
        assert_equal "Family", JSON.parse(output[:output])["results"].first["title"]
      end
    end
  end
  
  test "search_scenes asks for a description when the model sends none" do
    with_responses([scene_call("  ")], [answer_output("Sorry.")]) do |requests|
      events = SearchAgent.new("q").run
  
      assert_not events.first.result.ok?
      output = requests.last[:input].find { (_1[:type] || _1["type"]) == "function_call_output" }
      assert_match(/Describe the scene/, JSON.parse(output[:output])["error"])
    end
  end
  
  test "both tools are offered with strict schemas" do
    assert_equal %w[run_sql search_scenes], SearchAgent::TOOLS.map { _1[:name] }
    SearchAgent::TOOLS.each do |tool|
      params = tool[:parameters]
      assert_equal params[:properties].keys.map(&:to_s).sort, params[:required].sort
      assert_equal false, params[:additionalProperties]
    end
  end
  
  test "search events survive a round trip through the cache format" do
    found = { rank: 1, series: "TNG", episode: "episode 981", title: "Family", season: 4, episode_number: 2, similarity: 0.6, scene: "PICARD: Robert." }
    event = SearchAgent::Event.search(SearchAgent::SceneSearch.new(description: "brothers", episodes: [found], ms: 12), "why")
    assert_equal event, SearchAgent::Event.from_h(JSON.parse(event.to_h.to_json))
  end
  
  test "events survive a round trip through the cache format" do
    result = ReadonlySql::Result.new(sql: "SELECT 1", columns: ["x"], rows: [[1]], truncated: false, error: nil, ms: 3)
    event = SearchAgent::Event.sql(result, "why")
    assert_equal event, SearchAgent::Event.from_h(JSON.parse(event.to_h.to_json))
  end
end
