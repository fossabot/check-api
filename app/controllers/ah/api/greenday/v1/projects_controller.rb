class Ah::Api::Greenday::V1::ProjectsController < Ah::Api::Greenday::V1::BaseController
  before_action :check_if_team_exists, only: [:show, :collection]

  def index
    items = []
    user = User.current
    unless user.nil?
      user.team_users.each do |team_user|
        team_user = team_user.extend(Montage::ProjectUser)
        team = team_user.team.extend(Montage::Project)
        items << team.team_as_montage_project_json(team_user)
      end
    end
    json = {
      is_list: true,
      items: items
    }
    render json: json, status: 200
  end

  def create
    data = JSON.parse(request.raw_post)
    team = Team.new
    team.name = data['name']
    team.description = data['description']
    team.slug = Team.slug_from_name(data['name']) + '-' + Time.now.to_i.to_s
    team.save!
    team = team.extend(Montage::Project)
    team_user = TeamUser.where(team_id: team.id, user_id: User.current&.id).last.extend(Montage::ProjectUser)
    json = team.team_as_montage_project_json(team_user)
    render json: json, status: 200
  end

  def show
    return if @team.nil?
    team_user = TeamUser.where(team_id: @team.id, user_id: User.current&.id).last.extend(Montage::ProjectUser)
    json = @team.team_as_montage_project_json(team_user)
    render json: json, status: 200
  end

  def collection
    return if @team.nil?
    json = nil

    if request.get?
      items = []
      @team.projects.each do |project|
        project = project.extend(Montage::Collection)
        items << project.project_as_montage_collection_json
      end
      json = {
        is_list: true,
        items: items
      }
    elsif request.post?
      data = JSON.parse(request.raw_post)
      project = Project.create!(title: data['name'], team_id: data['project_id'])
      project = project.extend(Montage::Collection)
      json = project.project_as_montage_collection_json
    end

    render json: json, status: 200
  end

  private

  def check_if_team_exists
    id = params[:id]
    @team = Team.where(id: id).last.extend(Montage::Project)
    render(text: 'Not Found', status: 404) if @team.nil?
  end
end
