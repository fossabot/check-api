require File.join(File.expand_path(File.dirname(__FILE__)), '..', 'test_helper')

class GreendayCollectionsControllerTest < ActionController::TestCase
  def setup
    super
    @controller = Ah::Api::Greenday::V1::CollectionsController.new
    @request.env['devise.mapping'] = Devise.mappings[:api_user]
    sign_out('user')
    User.current = nil
  end

  test "should return error if collection does not exist" do
    u = create_omniauth_user info: { name: 'Test User' }
    authenticate_with_user(u)
    get :show, collection_id: 0, project_id: 0
    assert_response 404
  end

  test "should update collection" do
    u = create_omniauth_user info: { name: 'Test User' }
    authenticate_with_user(u)
    t = create_team
    create_team_user team: t, user: u, role: 'owner'
    p = create_project team: t, title: 'Foo'
    assert_equal 'Foo', p.reload.title
    @request.env['RAW_POST_DATA'] = { name: 'Bar' }.to_json
    post :update, collection_id: p.id, project_id: t.id
    assert_response :success
    assert_equal 'Bar', p.reload.title
  end

  test "should show collection" do
    u = create_omniauth_user info: { name: 'Test User' }
    authenticate_with_user(u)
    t = create_team
    p = create_project team: t, title: 'Foo'
    get :show, collection_id: p.id, project_id: t.id
    assert_response :success
  end
end 
