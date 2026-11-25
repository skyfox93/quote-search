# Lets search_agent_reader log in, so the AI agent's SQL runs on its own
# connection as that role (the `agent` entry in config/database.yml).
#
# Switching roles on the app's connection (SET LOCAL ROLE) isn't a boundary:
# the app logs in as a superuser, and a query can switch itself back with
# set_config('role', 'none', true). Logged in as the reader, there is nothing
# to switch back to, so Postgres's own privilege checks hold.
#
# Where logins need a password (production), set one separately, and give
# the app the same value in SEARCH_AGENT_DB_PASSWORD:
#   ALTER ROLE search_agent_reader PASSWORD '...';
class AllowSearchAgentReaderLogin < ActiveRecord::Migration[8.1]
  def up
    execute "ALTER ROLE search_agent_reader LOGIN"
  end

  def down
    execute "ALTER ROLE search_agent_reader NOLOGIN"
  end
end
