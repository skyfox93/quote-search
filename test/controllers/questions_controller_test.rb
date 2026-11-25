require "test_helper"

class QuestionsControllerTest < ActionDispatch::IntegrationTest
  test "index renders the question page and wires up the stream" do
    get ask_path(q: "Who talks most?")

    assert_response :success
    assert_select "[data-controller=agent][data-agent-url-value=?]", ask_stream_path(q: "Who talks most?")
    assert_select "#agent-steps"
  end

  test "stream needs a question" do
    get ask_stream_path
    assert_response :bad_request
  end

  test "stream explains a missing API key" do
    with_env("OPENAI_API_KEY" => nil) { get ask_stream_path(q: "Who talks most?") }

    assert_response :success
    assert_match(/<turbo-stream action="append" target="agent-steps">/, response.body)
    assert_match(/OPENAI_API_KEY/, response.body)
  end

  test "stream renders each step as an escaped turbo-stream" do
    result = ReadonlySql::Result.new(sql: "SELECT '<script>x</script>' AS c", columns: ["c"], rows: [["<script>x</script>"]],
                                     truncated: false, error: nil, ms: 2)
    found = { rank: 1, series: "TNG", episode: "episode 1", title: "<i>Family</i>", season: 4, episode_number: 2, similarity: 0.61, scene: "x" }
    scenes = SearchAgent::SceneSearch.new(description: "<u>brothers</u>", episodes: [found], ms: 9)
    events = [SearchAgent::Event.sql(result, "Look <b>up</b>"), SearchAgent::Event.search(scenes, "Find scenes"),
              SearchAgent::Event.answer("It's <img src=x onerror=alert(1)>.")]
    run = ->(&block) { events.each(&block); events }

    with_env("OPENAI_API_KEY" => "test-key") do
      agent = SearchAgent.new("q")
      stub_method(agent, :run, run) do
        stub_method(SearchAgent, :new, agent) { get ask_stream_path(q: "Who talks most?") }
      end
    end

    assert_response :success
    assert_equal 3, response.body.scan("<turbo-stream").size
    assert_match(/vector search · 1 episode/, response.body)
    assert_match(/0\.61/, response.body)
    assert_no_match(/<i>Family|<u>brothers/, response.body)
    assert_no_match(/<script>x/, response.body)
    assert_no_match(/<img/, response.body)
    assert_no_match(/<b>up/, response.body)
    assert_match(/&lt;script&gt;x&lt;\/script&gt;/, response.body)
  end
end
