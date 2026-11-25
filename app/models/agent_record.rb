# The database connection for the AI agent's SQL (ReadonlySql). It logs in
# as search_agent_reader (see the `agent` entry in config/database.yml),
# which can SELECT dialogues and episode_texts and nothing else.
class AgentRecord < ActiveRecord::Base
  self.abstract_class = true

  connects_to database: { writing: :agent }
end
