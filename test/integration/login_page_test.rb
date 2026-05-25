require "test_helper"

class LoginPageTest < ActionDispatch::IntegrationTest
  test "the login page heading is in Spanish" do
    get new_user_session_path

    assert_response :success
    assert_select "h2", text: "Iniciar sesión"
  end

  test "the login page does not link to registration" do
    get new_user_session_path

    assert_response :success
    assert_select "a[href=?]", new_user_registration_path, count: 0
  end
end
