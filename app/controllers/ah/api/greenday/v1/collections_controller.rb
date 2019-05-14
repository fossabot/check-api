class Ah::Api::Greenday::V1::CollectionsController < Ah::Api::Greenday::V1::BaseController
  before_action :check_if_project_exists, only: [:update, :show]
  
  def update
    return if @project.nil?
    data = JSON.parse(request.raw_post)
    @project.title = data['name'] unless data['name'].blank?
    @project.save!
    json = @project.project_as_montage_collection_json
    render json: json, status: 200
  end

  def show
    return if @project.nil?
    json = @project.project_as_montage_collection_json
    render json: json, status: 200
  end

  private

  def check_if_project_exists
    @project = Project.where(id: params['collection_id'], team_id: params['project_id']).last.extend(Montage::Collection)
    render(text: 'Not Found', status: 404) if @project.nil?
  end
end
