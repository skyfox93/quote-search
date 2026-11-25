require "test_helper"

class SearchQueryPlannerTest < ActiveSupport::TestCase
  def planner(query = "in what episode of TNG does Geordi become an assassin")
    SearchQueryPlanner.new(query)
  end

  def valid_output(**overrides)
    { "search_query" => "Geordi become an assassin", "series" => "TNG" }.merge(overrides.transform_keys(&:to_s))
  end

  test "keeps valid model output" do
    plan = planner.sanitize(valid_output)

    assert_equal "Geordi become an assassin", plan.query
    assert_equal({ series: "TNG" }, plan.filters)
    assert plan.rewritten
  end

  test "drops words the user didn't write" do
    plan = planner.sanitize(valid_output(search_query: "LAFORGE: Geordi becomes an assassin. The Mind's Eye, Romulan"))
    assert_equal "Geordi an assassin.", plan.query
  end

  test "matches the user's words regardless of case and punctuation" do
    plan = planner("Find where Scotty says \"he's dead, Jim\"").sanitize(valid_output(search_query: "scotty says He's dead, jim!"))
    assert_equal "scotty says He's dead, jim!", plan.query
  end

  test "falls back to the raw query when nothing the model wrote is the user's" do
    plan = planner("Data's cat").sanitize(valid_output(search_query: "Spot"))
    assert_equal "Data's cat", plan.query
  end

  test "drops a series outside the allow-list" do
    plan = planner.sanitize(valid_output(series: "TNG'; DROP TABLE episode_texts; --"))
    assert_empty plan.filters
    assert_not plan.filtered?
  end

  test "falls back to the raw query when the model returns no query" do
    plan = planner("Data's cat").sanitize("search_query" => "  ", "series" => nil)
    assert_equal "Data's cat", plan.query
  end

  test "handles output that is not an object" do
    plan = planner.sanitize(["not", "a", "hash"])
    assert_empty plan.filters
    assert plan.query.present?
  end

  test "truncates long queries" do
    plan = planner("a" * 5_000)
    assert_equal SearchQueryPlanner::MAX_QUERY_LENGTH, plan.sanitize(valid_output(search_query: "a" * 5_000)).query.length
  end

  test "schema lists every property as required, as strict mode needs" do
    schema = SearchQueryPlanner::SCHEMA
    assert_equal schema[:properties].keys.map(&:to_s).sort, schema[:required].sort
    assert_equal false, schema[:additionalProperties]
  end

  test "prompt lists the series codes" do
    EpisodeText::SERIES.each_key { |code| assert_includes SearchQueryPlanner::INSTRUCTIONS, code }
  end

  test "uses the raw query without filters when no API key is set" do
    with_env("OPENAI_API_KEY" => nil) do
      plan = SearchQueryPlanner.plan("Picard plays the flute")
      assert_equal "Picard plays the flute", plan.query
      assert_empty plan.filters
      assert_not plan.rewritten
    end
  end

  test "falls back to the raw query when the API fails" do
    with_env("OPENAI_API_KEY" => "test-key") do
      stub_method(OpenaiApi, :chat_json, ->(**) { raise OpenaiApi::Error, "boom" }) do
        plan = SearchQueryPlanner.plan("Picard plays the flute")
        assert_equal "Picard plays the flute", plan.query
        assert_not plan.rewritten
      end
    end
  end
end
