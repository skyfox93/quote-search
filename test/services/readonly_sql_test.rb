require "test_helper"

class ReadonlySqlTest < ActiveSupport::TestCase
  setup do
    EpisodeText.create!(series: "TNG", episode: "episode 970", title: "Test Episode", text: "PICARD: Make it so.")
    Dialogue.create!(series: "TNG", episode: "episode 970", character: "PICARD", line: "Make it so.")
  end

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

  test "caps rows and long values" do
    result = ReadonlySql.run("SELECT repeat('x', 1000) AS long FROM generate_series(1, 80)")

    assert result.ok?, result.error
    assert_equal ReadonlySql::MAX_ROWS, result.row_count
    assert result.truncated
    assert_equal ReadonlySql::CELL_CHARS, result.rows.first.first.length
  end

  test "blocks anything but a single SELECT" do
    assert_blocked "DELETE FROM dialogues", /single SELECT/
    assert_blocked "SELECT 1; DROP TABLE dialogues", /";"/
    assert_blocked "SELECT 1 -- comment", /"--"/
    assert_blocked "SELECT 1 /* comment */", /"\/\*"/
  end

  test "can't write, even through a CTE, SELECT INTO or locks" do
    assert_blocked "WITH d AS (DELETE FROM dialogues RETURNING *) SELECT count(*) FROM d"
    assert_blocked "WITH u AS (UPDATE episode_texts SET title = 'x' RETURNING 1) SELECT * FROM u"
    assert_blocked "SELECT * INTO evil FROM dialogues"
    assert_blocked "SELECT * FROM dialogues LIMIT 1 FOR UPDATE"

    assert_equal 0, EpisodeText.where(title: "x").count
    assert Dialogue.exists?(episode: "episode 970")
  end

  test "only the allowed tables can be read" do
    assert_blocked "SELECT * FROM quotes", /Only these tables/
    assert_blocked "SELECT * FROM schema_migrations", /Only these tables/
    assert_blocked "SELECT table_name FROM information_schema.tables", /Only these tables/
    assert_blocked "SELECT rolname FROM pg_authid", /pg_authid/
    assert_blocked "SELECT * FROM json_each('{}')", /Function scans/
  end

  test "dangerous functions are refused" do
    assert_blocked "SELECT pg_read_file('/etc/passwd')", /pg_read_file/
    assert_blocked %(SELECT "pg_read_file"('/etc/passwd')), /pg_read_file/
    assert_blocked "SELECT query_to_xml('select * from quotes', true, true, '')", /query_to_xml/
    assert_blocked "SELECT * FROM ts_stat('select searchable from quotes')", /ts_stat/
    assert_blocked "SELECT set_config('role', 'postgres', true)", /set_config/
    assert_blocked "SELECT pg_sleep(10)", /pg_sleep/
    assert_blocked %(SELECT * FROM U&"\\0071uotes"), /U&/
  end

  test "leaves the connection as it found it" do
    ReadonlySql.run("SELECT 1 AS x FROM dialogues LIMIT 1")
    ReadonlySql.run("DELETE FROM dialogues")

    conn = ActiveRecord::Base.connection
    assert_equal "off", conn.select_value("SHOW transaction_read_only")
    assert_not_equal ReadonlySql::ROLE, conn.select_value("SELECT current_user")
  end
end
