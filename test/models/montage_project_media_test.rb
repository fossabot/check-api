require_relative '../test_helper'

class MontageProjectMediaTest < ActiveSupport::TestCase
  def setup
    super
    WebMock.disable_net_connect!
  end

  test "should return number of duplicates" do
    m = create_media url: mock_youtube_video(random_string)
    pm = create_project_media media: m
    assert_equal 0, pm.extend(Montage::Video).duplicate_count
    3.times { create_project_media(media: m) }
    assert_equal 3, pm.extend(Montage::Video).duplicate_count
  end

  test "should return YouTube Data API data or empty hash" do
    pm = create_project_media.extend(Montage::Video)
    assert_nil pm.youtube_api_data['foo']
    ProjectMedia.any_instance.stubs(:embed).returns({ 'raw' => { 'api' => { 'foo' => 'bar' } } })
    pm = create_project_media.extend(Montage::Video)
    assert_equal 'bar', pm.youtube_api_data['foo']
    ProjectMedia.any_instance.unstub(:embed)
  end

  test "should return name" do
    pm = create_project_media.extend(Montage::Video)
    ProjectMedia.any_instance.stubs(:title).returns('Foo')
    assert_equal 'Foo', pm.name
    ProjectMedia.any_instance.unstub(:title)
  end

  test "should return notes" do
    pm = create_project_media.extend(Montage::Video)
    ProjectMedia.any_instance.stubs(:description).returns('Bar')
    assert_equal 'Bar', pm.notes
    ProjectMedia.any_instance.unstub(:description)
  end

  test "should return pretty created" do
    pm = create_project_media.extend(Montage::Video)
    ProjectMedia.any_instance.stubs(:created_at).returns(Time.parse('1989-01-25'))
    assert_equal 'Jan 25, 1989', pm.pretty_created
    ProjectMedia.any_instance.unstub(:created_at)
  end

  test "should return pretty publish date or empty" do
    pm = create_project_media.extend(Montage::Video)
    assert_equal '', pm.pretty_publish_date
    ProjectMedia.any_instance.stubs(:embed).returns({ 'raw' => { 'api' => { 'published_at' => Time.parse('1989-01-25').to_s } } })
    pm = create_project_media.extend(Montage::Video)
    assert_equal 'Jan 25, 1989', pm.pretty_publish_date
    ProjectMedia.any_instance.unstub(:embed)
  end

  test "should return project id" do
    t = create_team
    p = create_project team: t
    pm = create_project_media(project: p).extend(Montage::Video)
    assert_equal t.id, pm.project_id
  end

  test "should return number of tags" do
    pm = create_project_media.extend(Montage::Video)
    2.times { create_tag(annotated: pm) }
    2.times { create_tag }
    2.times { create_comment(annotated: pm) }
    assert_equal 2, pm.tag_count
  end

  test "should return YouTube id" do
    id = random_string
    m = create_media url: mock_youtube_video(id)
    pm = create_project_media(media: m).extend(Montage::Video)
    assert_equal id, pm.youtube_id
  end

  test "should return channel id" do
    id = random_string
    ProjectMedia.any_instance.stubs(:embed).returns({ 'raw' => { 'api' => { 'channel_id' => id } } })
    pm = create_project_media.extend(Montage::Video)
    assert_equal id, pm.channel_id
    ProjectMedia.any_instance.unstub(:embed)
  end

  test "should return channel name" do
    name = random_string
    ProjectMedia.any_instance.stubs(:embed).returns({ 'raw' => { 'api' => { 'channel_title' => name } } })
    pm = create_project_media.extend(Montage::Video)
    assert_equal name, pm.channel_name
    ProjectMedia.any_instance.unstub(:embed)
  end

  test "should return as JSON" do
    pm = create_project_media.extend(Montage::Video)
    assert_kind_of Hash, pm.project_media_as_montage_video_json
  end

  test "should return duration" do
    name = random_string
    ProjectMedia.any_instance.stubs(:embed).returns({ 'raw' => { 'api' => { 'duration' => 320 } } })
    pm = create_project_media.extend(Montage::Video)
    assert_equal 320, pm.duration
    ProjectMedia.any_instance.unstub(:embed)
  end

  test "should return pretty duration" do
    name = random_string
    ProjectMedia.any_instance.stubs(:embed).returns({ 'raw' => { 'api' => { 'duration' => 320 } } })
    pm = create_project_media.extend(Montage::Video)
    assert_equal '00:05:20', pm.pretty_duration
    ProjectMedia.any_instance.unstub(:embed)
  end

  protected

  def mock_youtube_video(id)
    pender_url = CONFIG['pender_url_private'] + '/api/medias'
    url = 'https://www.youtube.com/watch?v=' + id.to_s
    data = { url: url, provider: 'youtube', type: 'item' }
    response = '{"type":"media","data":' + data.to_json + '}'
    WebMock.stub_request(:get, pender_url).with({ query: { url: url } }).to_return(body: response)
    url
  end
end
