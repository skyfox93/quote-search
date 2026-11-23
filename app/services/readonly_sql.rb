# Runs one SELECT written by an AI agent, as safely as Postgres allows.
#
# The SQL is untrusted. Layers of defence, each enough to stop most misuse:
#   1. Text checks: a single SELECT/WITH statement, no comments, and none of
#      the functions that read server files or run SQL given as a string.
#   2. A read-only transaction (no writes, no DDL, no row locks), with a short
#      statement timeout, that is always rolled back.
#   3. EXPLAIN first: the plan may only read ALLOWED_TABLES.
#   4. When the `search_agent_reader` role exists and can read those tables
#      (see db/migrate/*_create_search_agent_reader_role.rb), the query runs
#      as that role, which can SELECT those tables and nothing else. This is
#      the real boundary; 1-3 still apply without it.
#   5. At most MAX_ROWS rows come back, each cell cut to CELL_CHARS.
class ReadonlySql
  ALLOWED_TABLES = %w[dialogues episode_texts].freeze
  ROLE = "search_agent_reader".freeze
  MAX_ROWS = 50
  CELL_CHARS = 300
  MAX_SQL_LENGTH = 4000
  TIMEOUT_MS = 4000

  # Functions that read files, call out of the database, or run SQL from a
  # string (which would get around the EXPLAIN table check).
  FORBIDDEN = /
    \b(?:pg_\w+|lo_\w+|dblink\w*|\w*_to_xml\w*|query_to_\w+|ts_stat|ts_rewrite|
         set_config|current_setting|copy|txid_\w+|xmlparse|xpath\w*)\b
    | ;                 # a second statement
    | --|\/\*           # comments (could hide text from these checks)
    | \bU&              # unicode-escaped identifiers
  /ix

  # Set-returning functions allowed in FROM.
  SAFE_SET_FUNCTIONS = %w[unnest generate_series regexp_matches regexp_split_to_table string_to_table].freeze

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

  def self.run(sql)
    new(sql).run
  end

  def initialize(sql)
    @sql = sql.to_s.strip.sub(/;\s*\z/, "")
  end

  def run
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    validate!
    columns, rows = execute
    truncated = rows.size > MAX_ROWS
    result(columns: columns, rows: rows.first(MAX_ROWS).map { |row| row.map { cell(_1) } }, truncated: truncated, started: started)
  rescue Error, ActiveRecord::StatementInvalid => e
    result(error: e.message.sub(/\APG::\w+: /, "").lines.first(3).join.strip.truncate(500), started: started)
  end

  def self.role_available?
    @role_available = check_role if @role_available.nil? || Rails.env.test?
    @role_available
  end

  def self.check_role
    conn = ActiveRecord::Base.connection
    return false unless conn.select_value("SELECT 1 FROM pg_roles WHERE rolname = #{conn.quote(ROLE)}")

    readable = ALLOWED_TABLES.all? do |table|
      conn.select_value("SELECT has_table_privilege(#{conn.quote(ROLE)}, #{conn.quote(table)}, 'SELECT')")
    end
    readable && conn.select_value("SELECT pg_has_role(current_user, #{conn.quote(ROLE)}, 'MEMBER')") == true
  rescue ActiveRecord::StatementInvalid
    false
  end

  private

  def validate!
    raise Error, "Empty query." if @sql.empty?
    raise Error, "Query is too long (max #{MAX_SQL_LENGTH} characters)." if @sql.length > MAX_SQL_LENGTH
    raise Error, "Only a single SELECT (or WITH ... SELECT) query is allowed." unless @sql.match?(/\A(?:select|with)\b/i)
    if (bad = @sql[FORBIDDEN])
      raise Error, "Not allowed in queries: #{bad.strip.inspect}. Use one plain SELECT on #{ALLOWED_TABLES.join(" / ")}."
    end
  end

  # Wrapping the query in a subquery caps the rows, and also rejects anything
  # that isn't a plain SELECT (e.g. SELECT ... INTO).
  def wrapped
    "SELECT * FROM (\n#{@sql}\n) AS agent_query LIMIT #{MAX_ROWS + 1}"
  end

  def execute
    conn = ActiveRecord::Base.connection
    output = nil
    conn.transaction(requires_new: true, joinable: false) do
      conn.execute("SET TRANSACTION READ ONLY")
      conn.execute("SET LOCAL statement_timeout = #{TIMEOUT_MS.to_i}")
      conn.execute("SET LOCAL ROLE #{conn.quote_column_name(ROLE)}") if self.class.role_available?
      check_tables!(conn)
      res = conn.exec_query(wrapped, "AgentSQL")
      output = [res.columns, res.rows]
      raise ActiveRecord::Rollback
    end
    output
  end

  def check_tables!(conn)
    plan = conn.select_value("EXPLAIN (FORMAT JSON, VERBOSE) #{wrapped}")
    plan = JSON.parse(plan) if plan.is_a?(String)
    relations = []
    walk = lambda do |node|
      case node
      when Hash
        relations << [node["Schema"], node["Relation Name"]] if node["Relation Name"]
        if node["Node Type"] == "Function Scan" && !SAFE_SET_FUNCTIONS.include?(node["Function Name"])
          raise Error, "Function scans aren't allowed (#{node["Function Name"]})."
        end
        node.each_value { walk.(_1) }
      when Array then node.each { walk.(_1) }
      end
    end
    walk.(plan)
    bad = relations.uniq.reject { |schema, name| schema == "public" && ALLOWED_TABLES.include?(name) }
    raise Error, "Only these tables can be queried: #{ALLOWED_TABLES.join(", ")}." if bad.any?
  end

  def cell(value)
    value.is_a?(String) ? value.truncate(CELL_CHARS) : value
  end

  def result(started:, columns: [], rows: [], truncated: false, error: nil)
    ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    Result.new(sql: @sql, columns: columns, rows: rows, truncated: truncated, error: error, ms: ms)
  end
end
