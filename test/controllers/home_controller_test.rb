require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "landing page explains the three levels with lazy examples" do
    get root_path

    assert_response :success
    assert_select "#level-1 .level__title", /Keyword search/
    assert_select "#level-2 .level__title", /RAG/
    assert_select "#level-3 .level__title", /agent/
    %w[keyword rag agent].each do |level|
      assert_select "turbo-frame#example-#{level}[loading=lazy][src=?]", landing_example_path(level)
    end
  end

  test "keyword example compares exact and dictionary matches" do
    Dialogue.create!(series: "TNG", episode: "episode 990", character: "BORG", line: "You will be assimilated.")
    Dialogue.create!(series: "TNG", episode: "episode 990", character: "PICARD", line: "They are assimilating the colony.")

    get landing_example_path("keyword")

    assert_response :success
    assert_select "turbo-frame#example-keyword"
    assert_select ".compare__item--win .compare__num", "2"
    assert_select ".quote-item mark", minimum: 1
  end

  test "AI examples explain when the API isn't available" do
    with_env("OPENAI_API_KEY" => nil) do
      get landing_example_path("rag")
      assert_select "turbo-frame#example-rag .example__note", /OpenAI API/
      get landing_example_path("agent")
      assert_select "turbo-frame#example-agent .example__note", /OpenAI API/
    end
  end

  test "unknown example levels aren't routed" do
    get "/examples/nope"
    assert_response :not_found
  end
end
