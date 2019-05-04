class Ah::Api::Greenday::V1::UsersController < Ah::Api::Greenday::V1::BaseController
  def me
    header = CONFIG['authorization_header'] || 'X-Token'
    token = request.headers[header]
    user = User.where(token: token).last || current_api_user
    json = {}
    unless user.nil?
      name = user.name.split(/\s/)
      json = {
        accepted_nda: !user.last_accepted_terms_at.blank?,
        date_joined: user.created_at.to_s,
        email: user.email,
        first_name: name.first ,
        id: user.id,
        is_active: true,
        is_googler: false,
        is_staff: false,
        is_superuser: user.is_admin,
        is_whitelisted: true,
        language: 'en',
        last_login: user.last_sign_in_at.to_s,
        last_name: name.last,
        profile_img_url: user.profile_image,
        username: user.login
      }
    end
    render json: json, status: 200
  end

  # FIXME: Return actual numbers
  def stats
    user = current_api_user
    json = {
      id: user&.id,
      tags_added: 0,
      videos_watched: 0
    }
    render json: json, status: 200
  end
end
