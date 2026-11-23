# A database role for the AI agent's SQL tool (ReadonlySql): it can read the
# transcript tables and nothing else, so agent queries can't touch other
# tables, write, or call superuser-only functions, whatever SQL they contain.
# The app's own user switches to it per query (SET LOCAL ROLE), so it needs
# no login or password.
#
# Roles are shared by every database on the server; the grants are per
# database. Creating a role needs CREATEROLE (or superuser).
class CreateSearchAgentReaderRole < ActiveRecord::Migration[8.1]
  ROLE = "search_agent_reader"
  TABLES = %w[dialogues episode_texts]

  def up
    execute <<~SQL
      DO $$
      BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '#{ROLE}') THEN
          CREATE ROLE #{ROLE} NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
        END IF;
      END
      $$;
    SQL
    execute "GRANT USAGE ON SCHEMA public TO #{ROLE}"
    execute "GRANT SELECT ON #{TABLES.join(", ")} TO #{ROLE}"
    execute "GRANT #{ROLE} TO CURRENT_USER"
  end

  def down
    execute "REVOKE SELECT ON #{TABLES.join(", ")} FROM #{ROLE}"
    execute "REVOKE USAGE ON SCHEMA public FROM #{ROLE}"
  end
end
