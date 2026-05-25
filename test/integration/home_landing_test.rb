require "test_helper"

class HomeLandingTest < ActionDispatch::IntegrationTest
  test "guests see the public landing" do
    get root_path

    assert_response :success
    assert_includes response.body, "Del horno a la puerta"
  end

  test "the landing offers a login entry point" do
    get root_path

    assert_response :success
    assert_select "a[href=?]", new_user_session_path, minimum: 1
  end

  test "the landing does not surface registration" do
    get root_path

    assert_response :success
    assert_select "a[href=?]", new_user_registration_path, count: 0
  end
end
