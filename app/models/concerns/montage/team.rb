module Montage::Project
  include Montage::Base

  def privacy_project
    self.private ? 1 : 2
  end

  # FIXME: Assuming that that team privacy setting applies to tags
  def privacy_tags
    self.privacy_project
  end

  def video_count
    ProjectMedia.joins(:project).joins(:media).where('projects.team_id' => self.id).where("medias.url LIKE 'https://www.youtube.com%'").count
  end

  def video_tag_instance_count
    Tag
    .joins("INNER JOIN project_medias ON project_medias.id = annotations.annotated_id INNER JOIN projects ON projects.id = project_medias.project_id")
    .where(annotation_type: 'tag')
    .where(annotated_type: 'ProjectMedia')
    .where('projects.team_id' => self.id)
    .count
  end

  def admin_ids
    self.team_users.where(role: 'owner', status: 'member').map(&:user_id)
  end

  def assigned_user_ids
    self.team_users.where(status: 'member').map(&:user_id)
  end
end
