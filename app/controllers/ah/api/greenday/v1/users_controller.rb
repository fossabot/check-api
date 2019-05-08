class Ah::Api::Greenday::V1::UsersController < Ah::Api::Greenday::V1::BaseController
  def me
    header = CONFIG['authorization_header'] || 'X-Token'
    token = request.headers[header]
    user = User.where(token: token).last || current_api_user
    json = {}
    unless user.nil?
      user = user.extend(Montage::User)
      json = {
        accepted_nda: user.accepted_nda,
        date_joined: user.date_joined,
        email: user.email,
        first_name: user.first_name,
        id: user.id,
        is_active: true,
        is_googler: false,
        is_staff: false,
        is_superuser: user.is_superuser,
        is_whitelisted: true,
        language: 'en',
        last_login: user.last_login,
        last_name: user.last_name,
        profile_img_url: user.profile_img_url,
        username: user.username
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
