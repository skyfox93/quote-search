# Runs one SELECT written by an AI agent.
#
# The SQL is untrusted, so the boundary is Postgres itself: the query runs on
# AgentRecord's connection, which logs in as search_agent_reader. That role
# can SELECT dialogues and episode_texts and nothing else, so Postgres
# refuses writes, other tables and superuser-only functions (reading files,
# for example), however the SQL is written. This class only adds what
# privileges can't express:
#   - the query is wrapped as a subquery, so it must be a single SELECT, and
#     at most MAX_ROWS rows come back (each cell cut to CELL_CHARS);
#   - a statement timeout, so a slow query can't tie up the database;
#   - a read-only transaction that is always rolled back, so nothing the
#     query sets (e.g. with set_config) carries over to the next one. Where
#     the agent shares the app's login (Heroku Essential, see database.yml)
#     this is what stops writes.
class ReadonlySql
  MAX_ROWS = 100
  CELL_CHARS = 300
  MAX_SQL_LENGTH = 4000
  TIMEOUT_MS = 4000

  class Error < StandardError; end

  Result = Data.define(:sql, :columns, :rows, :truncated, :error, :ms) do
    def ok? = error.nil?
    def row_count = rows.size

    # What the model sees: compact JSON.
    def to_model_json
      return { error: error }.to_json if error

      { columns: columns, rows: rows, row_count: row_count, truncated: truncated }.to_json
    end
  end

  def self.run(sql, timeout_ms: TIMEOUT_MS)
    new(sql, timeout_ms: timeout_ms).run
  end

  def initialize(sql, timeout_ms: TIMEOUT_MS)
    @sql = sql.to_s.strip.sub(/;\s*\z/, "")
    @timeout_ms = timeout_ms.to_i
  end

  def run
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    raise Error, "Empty query." if @sql.empty?
    raise Error, "Query is too long (max #{MAX_SQL_LENGTH} characters)." if @sql.length > MAX_SQL_LENGTH

    columns, rows = execute
    truncated = rows.size > MAX_ROWS
    result(columns: columns, rows: rows.first(MAX_ROWS).map { |row| row.map { cell(_1) } }, truncated: truncated, started: started)
  rescue Error, ActiveRecord::StatementInvalid => e
    result(error: e.message.sub(/\APG::\w+: /, "").lines.first(3).join.strip.truncate(500), started: started)
  rescue ActiveRecord::ConnectionNotEstablished => e
    Rails.logger.error("[readonly sql] can't connect as search_agent_reader: #{e.message}")
    result(error: "The SQL tool can't reach the database right now.", started: started)
  end

  private

  # A subquery can only hold one SELECT (or WITH ... SELECT), and the LIMIT
  # caps what Postgres sends back.
  def wrapped
    "SELECT * FROM (\n#{@sql}\n) AS agent_query LIMIT #{MAX_ROWS + 1}"
  end

  def execute
    AgentRecord.with_connection do |conn|
      output = nil
      conn.transaction(requires_new: true, joinable: false) do
        conn.execute("SET TRANSACTION READ ONLY")
        conn.execute("SET LOCAL statement_timeout = #{@timeout_ms}")
        res = conn.exec_query(wrapped, "AgentSQL")
        output = [res.columns, res.rows]
        raise ActiveRecord::Rollback
      end
      output
    end
  end

  def cell(value)
    value.is_a?(String) ? value.truncate(CELL_CHARS) : value
  end

  def result(started:, columns: [], rows: [], truncated: false, error: nil)
    ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    Result.new(sql: @sql, columns: columns, rows: rows, truncated: truncated, error: error, ms: ms)
  end
end
