require "test_helper"

# Queries run on the agent connection as search_agent_reader, so these check
# what Postgres itself refuses. They read the make_it_so fixtures: rows
# created inside a test aren't visible to that connection.
class ReadonlySqlTest < ActiveSupport::TestCase
  def assert_blocked(sql, message = nil)
    result = ReadonlySql.run(sql)
    assert_not result.ok?, "expected #{sql.inspect} to be blocked"
    assert_match message, result.error if message
    result
  end

  test "runs a SELECT and returns columns and rows" do
    result = ReadonlySql.run("SELECT character, count(*) AS n FROM dialogues WHERE episode = 'episode 970' GROUP BY character;")

    assert result.ok?, result.error
    assert_equal %w[character n], result.columns
    assert_equal [["PICARD", 1]], result.rows
    assert_equal({ "columns" => %w[character n], "rows" => [["PICARD", 1]], "row_count" => 1, "truncated" => false }, JSON.parse(result.to_model_json))
  end

  test "joins and CTEs are fine" do
    sql = "WITH d AS (SELECT * FROM dialogues) SELECT e.title FROM d JOIN episode_texts e ON e.series = d.series AND e.episode = d.episode WHERE d.episode = 'episode 970'"
    assert_equal [["Test Episode"]], ReadonlySql.run(sql).rows
  end

  test "runs as search_agent_reader, and a query can't switch back" do
    assert_equal [["search_agent_reader"]], ReadonlySql.run("SELECT current_user").rows
    assert_equal [["search_agent_reader"]], ReadonlySql.run("SELECT current_user FROM (SELECT set_config('role', 'none', true)) s").rows
  end

  test "caps rows and long values" do
    result = ReadonlySql.run("SELECT repeat('x', 1000) AS long FROM generate_series(1, 80)")

    assert result.ok?, result.error
    assert_equal ReadonlySql::MAX_ROWS, result.row_count
    assert result.truncated
    assert_equal ReadonlySql::CELL_CHARS, result.rows.first.first.length
  end

  test "only a single SELECT fits in the wrapper" do
    assert_blocked "DELETE FROM dialogues", /syntax error/
    assert_blocked "SELECT 1; DROP TABLE dialogues", /syntax error|multiple commands/
    assert_blocked "SELECT * INTO evil FROM dialogues", /INTO/
  end

  test "can't write, even through a CTE or a row lock" do
    assert_blocked "WITH d AS (DELETE FROM dialogues RETURNING *) SELECT count(*) FROM d"
    assert_blocked "SELECT * FROM dialogues LIMIT 1 FOR UPDATE", /read-only transaction/

    assert Dialogue.exists?(episode: "episode 970")
  end

  test "Postgres refuses other tables" do
    assert_blocked "SELECT * FROM quotes", /permission denied for table quotes/
    assert_blocked "SELECT * FROM schema_migrations", /permission denied/
    assert_blocked "SELECT * FROM episode_chunks", /permission denied/
    assert_blocked "SELECT rolname FROM pg_authid", /permission denied/

    tables = ReadonlySql.run("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY 1").rows.flatten
    assert_equal %w[dialogues episode_texts], tables, "the role only sees the tables it can read"
  end

  test "Postgres refuses superuser functions, including through SQL in a string" do
    assert_blocked "SELECT pg_read_file('/etc/passwd')", /permission denied for function pg_read_file/
    assert_blocked "SELECT query_to_xml('select * from quotes', true, true, '')", /permission denied for table quotes/
    assert_blocked "SELECT query_to_xml('select pg_read_file(''/etc/passwd'')', true, true, '') FROM (SELECT set_config('role', 'none', true)) s",
                   /permission denied for function pg_read_file/
  end

  test "slow queries time out" do
    result = ReadonlySql.run("SELECT pg_sleep(1)", timeout_ms: 50)
    assert_not result.ok?
    assert_match(/statement timeout/, result.error)
  end

  test "settings a query changes don't carry over" do
    ReadonlySql.run("SELECT set_config('search_path', 'pg_catalog', false)")
    assert_equal [["search_agent_reader"]], ReadonlySql.run("SELECT current_user FROM dialogues LIMIT 1").rows
    assert_not_equal [["pg_catalog"]], ReadonlySql.run("SELECT current_setting('search_path')").rows
  end
end
