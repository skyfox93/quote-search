require "test_helper"

class SearchQueryPlannerTest < ActiveSupport::TestCase
  def planner(query = "in what episode of TNG does Geordi become an assassin")
    SearchQueryPlanner.new(query)
  end

  def valid_output(**overrides)
    {
      "semantic_query" => "LAFORGE: (dazed) I have my orders.\nPICARD: Geordi?",
      "keyword_query" => "Geordi assassin Romulan",
      "series" => "TNG",
      "episode_guesses" => [{ "series" => "TNG", "title" => "The Mind's Eye" }]
    }.merge(overrides.transform_keys(&:to_s))
  end

  test "keeps valid model output" do
    plan = planner.sanitize(valid_output)

    assert_equal "LAFORGE: (dazed) I have my orders.\nPICARD: Geordi?", plan.query
    assert_equal "Geordi assassin Romulan", plan.keywords
    assert_equal({ series: "TNG" }, plan.filters)
    assert_equal [SearchQueryPlanner::Guess.new(series: "TNG", title: "The Mind's Eye")], plan.guesses
    assert plan.rewritten
  end

  test "keeps single line breaks in the script passage but squishes the rest" do
    plan = planner.sanitize(valid_output(semantic_query: "  PICARD:   Engage.  \n\n\n  RIKER: Aye.  "))
    assert_equal "PICARD: Engage.\nRIKER: Aye.", plan.query
  end

  test "drops a series outside the allow-list" do
    plan = planner.sanitize(valid_output(series: "TNG'; DROP TABLE episode_texts; --"))
    assert_empty plan.filters
    assert_not plan.filtered?
  end

  test "drops malformed guesses and guesses outside the filtered series" do
    plan = planner.sanitize(valid_output(episode_guesses: [
      { "series" => "XYZ", "title" => "Nope" },
      { "series" => "DS9", "title" => "Wrong series" },
      "not a hash",
      { "series" => "TNG", "title" => "   " },
      { "series" => "TNG", "title" => "Darmok" }
    ]))
    assert_equal ["Darmok"], plan.guesses.map(&:title)
  end

  test "keeps at most three guesses" do
    guesses = %w[A B C D E].map { { "series" => "TNG", "title" => _1 } }
    assert_equal 3, planner.sanitize(valid_output(episode_guesses: guesses)).guesses.size
  end

  test "empty or non-string keyword queries become nil" do
    assert_nil planner.sanitize(valid_output(keyword_query: "  ")).keywords
    assert_nil planner.sanitize(valid_output(keyword_query: 42)).keywords
    assert_nil planner.sanitize("semantic_query" => "x").keywords
  end

  test "falls back to the raw query when the model returns no semantic query" do
    plan = planner("Data's cat").sanitize("semantic_query" => "  ", "series" => nil)
    assert_equal "Data's cat", plan.query
  end

  test "handles output that is not an object" do
    plan = planner.sanitize(["not", "a", "hash"])
    assert_empty plan.filters
    assert_empty plan.guesses
    assert_nil plan.keywords
    assert plan.query.present?
  end

  test "truncates long values" do
    plan = planner.sanitize(valid_output(semantic_query: "a" * 5_000, keyword_query: "b" * 5_000,
                                         episode_guesses: [{ "series" => "TNG", "title" => "c" * 5_000 }]))
    assert_equal SearchQueryPlanner::MAX_QUERY_LENGTH, plan.query.length
    assert_equal SearchQueryPlanner::MAX_TITLE_LENGTH, plan.keywords.length
    assert_equal SearchQueryPlanner::MAX_TITLE_LENGTH, plan.guesses.first.title.length
  end

  test "schema lists every property as required, as strict mode needs" do
    schemas = [SearchQueryPlanner::SCHEMA, SearchQueryPlanner::SCHEMA.dig(:properties, :episode_guesses, :items)]
    schemas.each do |schema|
      assert_equal schema[:properties].keys.map(&:to_s).sort, schema[:required].sort
      assert_equal false, schema[:additionalProperties]
    end
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
      assert_empty plan.guesses
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
