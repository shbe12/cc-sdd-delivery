require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "defaults to rider" do
    user = User.new(email: "new@example.com", password: "password123")
    assert user.rider?
    assert_not user.manager?
  end

  test "can be a manager" do
    user = User.create!(email: "boss@example.com", password: "password123", role: :manager)
    assert user.manager?
    assert_includes User.manager, user
  end

  test "assigned_orders association exists" do
    user = User.new(role: :rider)
    assert_respond_to user, :assigned_orders
  end
end
