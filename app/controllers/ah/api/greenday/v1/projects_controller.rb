class Ah::Api::Greenday::V1::ProjectsController < Ah::Api::Greenday::V1::BaseController
  # FIXME: Return projects
  def index
    json = {
      is_list: true,
      items: []
    }
    render json: json, status: 200
  end
end
