ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# ReadonlySql logs in as search_agent_reader (AgentRecord). Test databases
# are built from schema.rb, which has no grants, so this gives the role the
# same SELECT it has in development, and points the agent connection at the
# database the tests are using (each parallel worker has its own).
module AgentDatabase
  def self.prepare
    ActiveRecord::Base.with_connection do |conn|
      conn.execute("GRANT USAGE ON SCHEMA public TO search_agent_reader")
      conn.execute("GRANT SELECT ON dialogues, episode_texts TO search_agent_reader")
      agent = ActiveRecord::Base.configurations.configs_for(env_name: "test", name: "agent", include_hidden: true)
      agent._database = conn.pool.db_config.database
    end
    AgentRecord.connects_to database: { writing: :agent }
  end
end
AgentDatabase.prepare

class ActiveSupport::TestCase
  # Run tests in parallel with specified workers
  parallelize(workers: :number_of_processors)
  parallelize_setup { AgentDatabase.prepare }

  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  # Add more helper methods to be used by all tests here...
end

module StubHelpers
  # Replaces obj.name (e.g. a class method) for the duration of the block.
  # impl is a callable, or a value to return.
  def stub_method(obj, name, impl)
    original = obj.method(name)
    obj.define_singleton_method(name) { |*args, **kwargs, &blk| impl.respond_to?(:call) ? impl.call(*args, **kwargs, &blk) : impl }
    yield
  ensure
    obj.define_singleton_method(name, original)
  end

  # Sets environment variables for the duration of the block (nil unsets).
  def with_env(vars)
    old = vars.keys.to_h { |k| [k, ENV[k]] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| ENV[k] = v }
  end
end

ActiveSupport::TestCase.include(StubHelpers)
ActionDispatch::IntegrationTest.include(StubHelpers)
