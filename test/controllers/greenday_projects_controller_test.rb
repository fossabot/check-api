require File.join(File.expand_path(File.dirname(__FILE__)), '..', 'test_helper')

class GreendayProjectsControllerTest < ActionController::TestCase
  def setup
    super
    @controller = Ah::Api::Greenday::V1::ProjectsController.new
    @request.env['devise.mapping'] = Devise.mappings[:api_user]
    sign_out('user')
    User.current = nil
  end

  test "should get projects as a list" do
    u = create_omniauth_user info: { name: 'Test User' }
    authenticate_with_user(u)
    get :index
    assert_response :success
    response = JSON.parse(@response.body)
    assert response['is_list']
    assert_kind_of Array, response['items']
  end

  test "should create project" do
    u = create_omniauth_user info: { name: 'Test User' }
    authenticate_with_user(u)
    assert_difference 'Team.count' do
      @request.env['RAW_POST_DATA'] = { name: 'Foo', description: 'Bar' }.to_json
      post :create
      assert_response :success
    end
  end
end
