require File.join(File.expand_path(File.dirname(__FILE__)), '..', 'test_helper')

class GreendayProjectsControllerTest < ActionController::TestCase
  def setup
    super
    @controller = Ah::Api::Greenday::V1::ProjectsController.new
    @request.env['devise.mapping'] = Devise.mappings[:api_user]
    sign_out('user')
    User.current = nil
    WebMock.disable_net_connect!
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

  test "should get project" do
    name = random_string
    t = create_team name: name
    u = create_omniauth_user
    create_team_user team: t, user: u
    authenticate_with_user(u)
    get :show, id: t.id
    assert_response :success
    response = JSON.parse(@response.body)
    assert_equal name, response['name']
  end

  test "should return error if project was not found" do
    name = random_string
    t = create_team name: name
    u = create_omniauth_user
    create_team_user team: t, user: u
    authenticate_with_user(u)
    get :show, id: 0
    assert_response 404
  end

  test "should return a collection" do
    t = create_team
    u = create_user
    2.times { create_project(team: t) }
    create_team_user team: t, user: u
    authenticate_with_user(u)
    get :collection, id: t.id
    assert_response :success
    response = JSON.parse(@response.body)
    assert_equal 2, response['items'].size
  end

  test "should create a collection" do
    t = create_team
    u = create_user
    create_team_user team: t, user: u, role: 'owner'
    authenticate_with_user(u)
    @request.env['RAW_POST_DATA'] = { name: 'Foo', project_id: t.id }.to_json
    assert_difference 'Project.count' do
      post :collection, id: t.id
    end
  end

  test "should create videos in batches and return errors" do
    t = create_team
    p = create_project team: t
    u = create_user
    create_team_user team: t, user: u, role: 'owner'
    authenticate_with_user(u)
    
    pender_url = CONFIG['pender_url_private'] + '/api/medias'
    
    url = 'https://www.youtube.com/watch?v=abc'
    data = { url: url, provider: 'youtube', type: 'profile' }
    response = '{"type":"media","data":' + data.to_json + '}'
    WebMock.stub_request(:get, pender_url).with({ query: { url: url } }).to_return(body: response)

    url = 'https://www.youtube.com/watch?v=xyz'
    data = { url: url, provider: 'youtube', type: 'item' }
    response = '{"type":"media","data":' + data.to_json + '}'
    WebMock.stub_request(:get, pender_url).with({ query: { url: url } }).to_return(body: response)

    WebMock.stub_request(:head, "/http:\/\/localhost.*/")

    @request.env['RAW_POST_DATA'] = { youtube_ids: ['abc', 'xyz'] }.to_json
    assert_difference 'ProjectMedia.count' do
      post :batch_create, id: t.id
    end
    assert_response :success
    response = JSON.parse(@response.body)
    assert_equal 1, response['videos'].size
    assert_equal 2, response['items'].size
  end

  test "should return videos" do
    pender_url = CONFIG['pender_url_private'] + '/api/medias'
    url = 'https://www.youtube.com/watch?v=123'
    data = { url: url, provider: 'youtube', type: 'item' }
    response = '{"type":"media","data":' + data.to_json + '}'
    WebMock.stub_request(:get, pender_url).with({ query: { url: url } }).to_return(body: response)
    m = create_media url: url

    t = create_team
    p = create_project team: t
    2.times { create_project_media(project: p) }
    create_project_media project: p, media: m
    u = create_user
    create_team_user team: t, user: u, role: 'owner'
    authenticate_with_user(u)

    get :video, id: t.id
    assert_response :success
    response = JSON.parse(@response.body)
    assert_equal 1, response['items'].size
  end
end
