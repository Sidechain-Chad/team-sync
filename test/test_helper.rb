ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...

    # Counts SQL queries executed inside the block, excluding schema/
    # transaction chatter.
    def count_queries(&block)
      count = 0
      counter = ->(*, payload) {
        next if payload[:name].in?(["SCHEMA", "TRANSACTION"])
        next if payload[:sql].start_with?("BEGIN", "COMMIT")
        count += 1
      }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
      count
    end

    # Fails if the block runs more than `n` queries. Use this to pin an N+1
    # fix in place — the real detector is asserting the count stays FLAT as
    # the dataset grows, not just that it's "low" for one size (see
    # BoardsControllerTest's "query count stays flat" test).
    def assert_max_queries(n, &block)
      count = count_queries(&block)
      assert count <= n, "Expected at most #{n} queries, got #{count}"
    end
  end
end
