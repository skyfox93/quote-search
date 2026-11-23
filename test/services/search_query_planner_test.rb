require "test_helper"

class SearchQueryPlannerTest < ActiveSupport::TestCase
  def planner(query = "in what episode of TNG does Geordi become an assassin")
    SearchQueryPlanner.new(query)
  end

  test "keeps valid model output" do
    plan = planner.sanitize(
      "semantic_query" => "Geordi is brainwashed into becoming an assassin",
      "keyword_query" => "Geordi assassin",
      "series" => "TNG"
    )

    assert_equal "Geordi is brainwashed into becoming an assassin", plan.query
    assert_equal "Geordi assassin", plan.keywords
    assert_equal({ series: "TNG" }, plan.filters)
    assert plan.rewritten
  end

  test "drops a series outside the allow-list" do
    plan = planner.sanitize("semantic_query" => "x", "series" => "TNG'; DROP TABLE episode_texts; --")
    assert_empty plan.filters
    assert_not plan.filtered?
  end

  test "empty or non-string keyword queries become nil" do
    assert_nil planner.sanitize("semantic_query" => "x", "keyword_query" => "  ").keywords
    assert_nil planner.sanitize("semantic_query" => "x", "keyword_query" => 42).keywords
    assert_nil planner.sanitize("semantic_query" => "x").keywords
  end

  test "falls back to the raw query when the model returns no semantic query" do
    plan = planner("Data's cat").sanitize("semantic_query" => "  ", "series" => nil)
    assert_equal "Data's cat", plan.query
  end

  test "handles output that is not an object" do
    plan = planner.sanitize(["not", "a", "hash"])
    assert_empty plan.filters
    assert_nil plan.keywords
    assert plan.query.present?
  end

  test "truncates long queries" do
    plan = planner.sanitize("semantic_query" => "a" * 2_000, "keyword_query" => "b" * 2_000)
    assert_equal SearchQueryPlanner::MAX_QUERY_LENGTH, plan.query.length
    assert_equal SearchQueryPlanner::MAX_QUERY_LENGTH, plan.keywords.length
  end

  test "schema lists every property as required, as strict mode needs" do
    schema = SearchQueryPlanner::SCHEMA
    assert_equal schema[:properties].keys.map(&:to_s).sort, schema[:required].sort
  end

  test "prompt lists the series codes" do
    EpisodeText::SERIES.each_key { |code| assert_includes SearchQueryPlanner::INSTRUCTIONS, code }
  end

  test "uses the raw query without filters when no API key is set" do
    with_env("OPENAI_API_KEY" => nil) do
      plan = SearchQueryPlanner.plan("Picard plays the flute")
      assert_equal "Picard plays the flute", plan.query
      assert_nil plan.keywords
      assert_empty plan.filters
      assert_not plan.rewritten
    end
  end

  private

  def with_env(vars)
    old = vars.keys.to_h { |k| [k, ENV[k]] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| ENV[k] = v }
  end
end
