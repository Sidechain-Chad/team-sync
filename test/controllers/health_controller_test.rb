require "test_helper"
require "minitest/mock"

# HealthController is what Render's healthCheckPath actually points at (see
# render.yaml) — /up is the default Rails health check and stays green even
# when Postgres is unreachable, which is the exact gap that let 23 deploys
# report healthy while every page 500'd. The point of this file is the 503
# case: a health check that has never been seen to fail is the bug being
# fixed, so the happy path alone would prove nothing.
class HealthControllerTest < ActionDispatch::IntegrationTest
  test "returns 200 when the database is reachable" do
    get health_check_path

    assert_response :success
  end

  test "returns 503 when the database is unreachable" do
    # Simulated, not a real outage: stubbing the exact call HealthController
    # makes is what "simulate the failure" means here — an actual dropped
    # connection would depend on infrastructure this suite doesn't control,
    # and would risk leaving the shared test connection broken for whichever
    # test runs next.
    ActiveRecord::Base.connection.stub(:execute, ->(*) { raise PG::ConnectionBad, "simulated outage" }) do
      get health_check_path
    end

    assert_response :service_unavailable
  end

  test "does not require authentication" do
    get health_check_path

    assert_response :success
  end

  test "the plain /up route is untouched and still does not check the database" do
    get rails_health_check_path

    assert_response :success
  end
end
