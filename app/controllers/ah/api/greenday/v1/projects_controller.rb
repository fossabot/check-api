class Ah::Api::Greenday::V1::ProjectsController < Ah::Api::Greenday::V1::BaseController
  def index
    items = []
    user = User.current
    unless user.nil?
      user.team_users.each do |team_user|
        team_user = team_user.extend(Montage::ProjectUser)
        team = team_user.team.extend(Montage::Project)
        items << {
          created: team.created,
          current_user_info: team_user.as_current_user_info,
          id: team.id,
          modified: team.modified,
          name: team.name,
          privacy_project: team.privacy_project,
          privacy_tags: team.privacy_tags,
          video_count: team.video_count,
          video_tag_instance_count: team.video_tag_instance_count
        }
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
    owner = TeamUser.where(team_id: team.id, role: 'owner', status: 'member').first.user.extend(Montage::User)

    json = {
      admin_ids: team.admin_ids,
      assigned_user_ids: team.assigned_user_ids,
      created: team.created,
      current_user_info: team_user.as_current_user_info,
      description: team.description,
      id: team.id,
      modified: team.modified, 
      name: team.name,
      owner: {
        email: owner.email, 
        first_name: owner.first_name, 
        id: owner.id, 
        last_name: owner.last_name, 
        profile_img_url: owner.profile_img_url
      }, 
      privacy_project: team.privacy_project, 
      privacy_tags: team.privacy_tags, 
      video_tag_instance_count: team.video_tag_instance_count
    }

    render json: json, status: 200
  end
end
