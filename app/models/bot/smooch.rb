require 'digest'

class Bot::Smooch
  ::Workflow::VerificationStatus.class_eval do
    check_workflow from: :any, to: :any, actions: :replicate_status_to_children
    check_workflow from: :any, to: :terminal, actions: :reply_to_smooch_users
    check_workflow from: :any, to: :any, actions: :reset_meme
    check_workflow from: :terminal, to: :non_terminal, actions: :reply_to_smooch_users_not_final
  end

  ::Relationship.class_eval do
    after_create :inherit_status_from_parent
    after_destroy :reset_child_status

    private

    def inherit_status_from_parent
      return if self.user.nil? || self.user.type == 'BotUser'
      target = self.target
      parent = self.source
      if Bot::Smooch.team_has_smooch_bot_installed(target)
        s = target.annotations.where(annotation_type: 'verification_status').last&.load
        status = parent.last_verification_status
        if !s.nil? && s.status != status
          s.status = status
          s.save!
        end
        Bot::Smooch.delay_for(1.second, { queue: 'smooch', retry: 0 }).send_meme_from_parent(parent.id, target.id)
      end
    end

    def reset_child_status
      target = self.target
      s = target.annotations.where(annotation_type: 'verification_status').last&.load
      status = ::Workflow::Workflow.options(target, 'verification_status')[:default]
      if !s.nil? && s.status != status
        s.status = status
        s.save!
      end
    end
  end

  ::Dynamic.class_eval do
    after_save :send_meme_to_smooch_users, if: proc { |d| d.annotation_type == 'memebuster' }

    private

    def send_meme_to_smooch_users
      SmoochMemeWorker.perform_in(1.second, self.id) if self.action == 'publish'
    end
  end

  ::DynamicAnnotation::Field.class_eval do
    protected

    def replicate_status_to_children
      pm = self.annotation.annotated
      return unless Bot::Smooch.team_has_smooch_bot_installed(pm)
      ::Bot::Smooch.delay_for(1.second, { queue: 'smooch', retry: 0 }).replicate_status_to_children(self.annotation.annotated_id, self.value, User.current&.id, Team.current&.id)
    end

    def reply_to_smooch_users
      ::Bot::Smooch.delay_for(1.second, { queue: 'smooch', retry: 0 }).reply_to_smooch_users(self.annotation.annotated_id, self.value)
    end

    def reply_to_smooch_users_not_final
      ::Bot::Smooch.delay_for(1.second, { queue: 'smooch', retry: 0 }).reply_to_smooch_users_not_final(self.annotation.annotated_id, self.value_was)
    end

    def reset_meme
      meme = Dynamic.where(annotation_type: 'memebuster', annotated_type: self.annotation&.annotated_type, annotated_id: self.annotation&.annotated_id).last
      unless meme.nil?
        FileUtils.rm_f(meme.memebuster_filepath)
        status = ::Workflow::Workflow.get_status(self.annotation.annotated, 'verification_status', self.value)
        meme.set_fields = {
          memebuster_status: ::Bot::Smooch.get_status_label(self.annotation.annotated, self.value, I18n.locale),
          memebuster_overlay: status&.dig('style', 'backgroundColor')
        }.to_json
        meme.skip_check_ability = true
        meme.save!
      end
    end
  end

  SMOOCH_PAYLOAD_JSON_SCHEMA = {
    type: 'object',
    required: ['trigger', 'app', 'version', 'appUser'],
    properties: {
      trigger: {
        type: 'string'
      },
      app: {
        type: 'object',
        required: ['_id'],
        properties: {
          '_id': {
            type: 'string'
          }
        }
      },
      version: {
        type: 'string'
      },
      messages: {
        type: 'array',
        items: {
          type: 'object',
          required: ['type'],
          properties: {
            type: {
              type: 'string'
            },
            text: {
              type: 'string'
            },
            mediaUrl: {
              type: 'string'
            },
            role: {
              type: 'string'
            },
            received: {
              type: 'number'
            },
            name: {
              type: 'string'
            },
            authorId: {
              type: 'string'
            },
            '_id': {
              type: 'string'
            },
            source: {
              type: 'object',
              properties: {
                type: {
                  type: 'string'
                },
                integrationId: {
                  type: 'string'
                }
              }
            }
          }
        }
      },
      appUser: {
        type: 'object',
        properties: {
          '_id': {
            type: 'string'
          },
          'conversationStarted': {
            type: 'boolean'
          }
        }
      }
    }
  }

  def self.team_has_smooch_bot_installed(pm)
    bot = TeamBot.where(identifier: 'smooch').last
    !TeamBotInstallation.where(team_id: pm.project.team_id, team_bot_id: bot.id).last.nil?
  end

  def self.convert_numbers(str)
    return nil if str.blank?
    altzeros = [0x0030, 0x0660, 0x06F0, 0x07C0, 0x0966, 0x09E6, 0x0A66, 0x0AE6, 0x0B66, 0x0BE6, 0x0C66, 0x0CE6, 0x0D66, 0x0DE6, 0x0E50, 0x0ED0, 0x0F20, 0x1040, 0x1090, 0x17E0, 0x1810, 0x1946, 0x19D0, 0x1A80, 0x1A90, 0x1B50, 0x1BB0, 0x1C40, 0x1C50, 0xA620, 0xA8D0, 0xA900, 0xA9D0, 0xA9F0, 0xAA50, 0xABF0, 0xFF10]
    digits = altzeros.flat_map { |z| ((z.chr(Encoding::UTF_8))..((z+9).chr(Encoding::UTF_8))).to_a }.join('')
    replacements = "0123456789" * altzeros.size
    str.tr(digits, replacements).to_i
  end

  def self.get_installation(key, value)
    bot = TeamBot.where(identifier: 'smooch').last
    return nil if bot.nil?
    smooch_bot_installation = nil
    TeamBotInstallation.where(team_bot_id: bot.id).each do |installation|
      smooch_bot_installation = installation if installation.settings.with_indifferent_access[key] == value
    end
    settings = smooch_bot_installation&.settings || {}
    RequestStore.store[:smooch_bot_settings] = settings.with_indifferent_access.merge({ team_id: smooch_bot_installation&.team_id.to_i })
    smooch_bot_installation
  end

  def self.valid_request?(request)
    RequestStore.store[:smooch_bot_queue] = request.headers['X-Check-Smooch-Queue'].to_s
    key = request.headers['X-API-Key'].to_s
    installation = self.get_installation('smooch_webhook_secret', key)
    !key.blank? && !installation.nil?
  end

  def self.config
    RequestStore.store[:smooch_bot_settings]
  end

  def self.webhook(request)
    # TODO This should be packaged as an event "invoke_webhook" + data payload
    Bot::Smooch.run(request.body.read)
  end

  def self.run(body)
    begin
      json = JSON.parse(body)
      JSON::Validator.validate!(SMOOCH_PAYLOAD_JSON_SCHEMA, json)
      case json['trigger']
      when 'message:appUser'
        json['messages'].each do |message|
          self.process_message(message, json['app']['_id'])
        end
        true
      when 'message:delivery:failure'
        self.resend_message(json)
        true
      else
        false
      end
    rescue StandardError => e
      Rails.logger.error("[Smooch Bot] Exception for trigger #{json&.dig('trigger') || 'unknown'}: #{e.message}")
      Airbrake.notify(e) if Airbrake.configuration.api_key
      raise(e) if e.is_a?(AASM::InvalidTransition) # Race condition: return 500 so Smooch can retry it later
      false
    end
  end

  def self.resend_message(message)
    code = begin message['error']['underlyingError']['errors'][0]['code'] rescue 0 end
    if code == 470
      self.delay_for(1.second, { queue: 'smooch', retry: 0 }).resend_message_after_window(message.to_json)
    end
  end

  def self.get_status_label(pm, status, lang)
    label = I18n.t('statuses.media.' + status.gsub(/^false$/, 'not_true') + '.label', locale: lang)
    ::Workflow::Workflow.options(pm, 'verification_status').with_indifferent_access['statuses'].each { |s| label = s['label'] if s['id'] == status } if lang.to_s == 'en'
    label
  end

  def self.resend_message_after_window(message)
    message = JSON.parse(message)
    self.get_installation('smooch_app_id', message['app']['_id'])
    pm_id = Rails.cache.read('smooch:response:' + message['message']['_id']).to_i
    pm = ProjectMedia.where(id: pm_id).last
    unless pm.nil?
      lang = Bot::Alegre.default.language_object(pm, :value)
      status = self.get_status_label(pm, pm.last_verification_status, lang)
      fallback = I18n.t(:smooch_bot_result, locale: lang, status: status, url: Bot::Smooch.embed_url(pm))
      ::Bot::Smooch.send_message_to_user(message['appUser']['_id'], "&[#{fallback}](#{self.config['smooch_template_namespace']}, check_verification_results, #{status}, #{Bot::Smooch.embed_url(pm)})")
    end
  end

  def self.get_language(message)
    text = message['text'].to_s
    lang = text.blank? ? nil : Bot::Alegre.default.get_language_from_alegre(text)
    lang = 'en' if lang.blank? || !I18n.available_locales.include?(lang.to_sym)
    lang
  end

  def self.banned_message?(message)
    # For now we only reject messages that match the following:
    # - the number 1
    # - user is banned
    self.convert_numbers(message['text']) == 1 || !Rails.cache.read("smooch:banned:#{message['authorId']}").nil?
  end

  def self.message_hash(message)
    hash = nil
    case message['type']
    when 'text'
      hash = Digest::MD5.hexdigest(self.get_text_from_message(message))
    when 'image', 'file'
      open(message['mediaUrl']) do |f|
        hash = Digest::MD5.hexdigest(f.read)
      end
    end
    hash
  end

  def self.process_message(message, app_id)
    lang = message['language'] = self.get_language(message)
    sm = CheckStateMachine.new(message['authorId'])
    if sm.state.value == 'waiting_for_message' && !self.banned_message?(message)
      hash = self.message_hash(message)
      pm_id = Rails.cache.read("smooch:message:#{hash}")
      if pm_id.nil?
        sm.send_message_new
        sm.message = message.to_json
        self.send_message_to_user(message['authorId'], I18n.t(:smooch_bot_ask_for_confirmation, locale: lang))
      else
        sm.send_message_existing
        self.save_message_later(message, app_id)
        self.send_message_to_user(message['authorId'], I18n.t(:smooch_bot_message_confirmed, locale: lang))
      end

    elsif sm.state.value == 'waiting_for_confirmation'
      sm.confirm_message
      saved_message = JSON.parse(sm.message.value)
      lang = saved_message['language']
      if self.convert_numbers(message['text']) == 1
        if self.supported_message?(saved_message)
          self.save_message_later(saved_message, app_id)
          self.send_message_to_user(message['authorId'], I18n.t(:smooch_bot_message_confirmed, locale: lang))
        else
          self.send_message_to_user(message['authorId'], I18n.t(:smooch_bot_message_type_unsupported, locale: lang))
        end
      else
        self.send_message_to_user(message['authorId'], I18n.t(:smooch_bot_message_unconfirmed, locale: lang))
      end
    end

    self.schedule_reminder_job(message['authorId'], app_id, sm)
  end

  def self.schedule_reminder_job(uid, app_id, sm)
    return if self.config['smooch_window_duration'].to_i == 0

    # Cancel previous reminder.
    self.cancel_reminder_job(uid)

    # Don't schedule a reminder if we're waiting for confirmation, because it will confuse users.
    if sm.state.value == 'waiting_for_message'
      job_id = SmoochPingWorker.perform_in(self.config['smooch_window_duration'].to_i.hours, uid, app_id)
      Rails.cache.write("smooch:reminder:#{uid}", job_id)
    end
  end

  def self.get_text_from_message(message)
    text = message['text'][/[^\s]+\.[^\s]+/, 0].to_s.gsub(/^https?:\/\//, '')
    text = message['text'] if text.blank?
    text.downcase
  end

  def self.supported_message?(message)
    case message['type']
    when 'text', 'image'
      return true
    when 'file'
      return message['mediaType'].to_s =~ /^image\//
    else
      return false
    end
  end

  def self.send_message_to_user(uid, text, extra = {})
    payload = { scope: 'app' }
    jwtHeader = { kid: self.config['smooch_secret_key_key_id'] }
    token = JWT.encode payload, self.config['smooch_secret_key_secret'], 'HS256', jwtHeader
    config = SmoochApi::Configuration.new
    config.api_key['Authorization'] = token
    config.api_key_prefix['Authorization'] = 'Bearer'
    api_client = SmoochApi::ApiClient.new(config)

    api_instance = SmoochApi::ConversationApi.new(api_client)
    app_id = self.config['smooch_app_id']
    params = { 'role' => 'appMaker', 'type' => 'text', 'text' => text }.merge(extra)
    message_post_body = SmoochApi::MessagePost.new(params)
    begin
      api_instance.post_message(app_id, uid, message_post_body)
    rescue SmoochApi::ApiError => e
      Rails.logger.error("[Smooch Bot] Exception when sending message #{params.inspect}: #{e.response_body}")
      Airbrake.notify(e) if Airbrake.configuration.api_key
    end
  end

  def self.get_queue
    mapping = { 'siege' => 'siege' }
    queue = RequestStore.store[:smooch_bot_queue].to_s
    queue.blank? ? 'smooch' : (mapping[queue] || 'smooch')
  end

  def self.save_message_later(message, app_id)
    type = (message['type'] == 'text' && !message['text'][/https?:\/\/[^\s]+/, 0].blank?) ? 'link' : message['type']
    SmoochWorker.set(queue: self.get_queue).perform_in(1.second, message.to_json, type, app_id)
  end

  def self.save_message(message_json, app_id)
    message = JSON.parse(message_json)
    self.get_installation('smooch_app_id', app_id)
    message['project_id'] = self.get_project_id(message)

    pm = case message['type']
         when 'text'
           self.save_text_message(message)
         when 'image'
           self.save_image_message(message)
         when 'file'
           message['mediaType'].to_s =~ /^image\// ? self.save_image_message(message) : return
         else
           return
         end

    return if pm.nil?

    # Remember that we received this message.
    hash = self.message_hash(message)
    Rails.cache.write("smooch:message:#{hash}", pm.id)

    # Only save the annotation for the same requester once.
    key = 'smooch:request:' + message['authorId'] + ':' + pm.id.to_s
    if !Rails.cache.read(key)
      a = Dynamic.new
      a.skip_check_ability = true
      a.skip_notifications = true
      a.disable_es_callbacks = Rails.env.to_s == 'test'
      a.annotation_type = 'smooch'
      a.annotated = pm
      a.set_fields = { smooch_data: message.merge({ app_id: app_id }).to_json }.to_json
      a.save!
    end
    Rails.cache.write(key, hash)

    self.send_results_if_item_is_finished(pm, message)
  end

  def self.send_results_if_item_is_finished(pm, message)
    if pm.is_finished?
      self.send_verification_results_to_user(message['authorId'], pm, pm.last_verification_status, message['language'])
      self.send_meme_to_user(message['authorId'], pm, message['language'])
    end
  end

  def self.get_project_id(_message)
    project_id = self.config['smooch_project_id'].to_i
    raise "Project ID #{project_id} does not belong to team #{self.config['team_id']}" if Project.where(id: project_id, team_id: self.config['team_id'].to_i).last.nil?
    project_id
  end

  def self.extract_url(text)
    begin
      urls = Twitter::Extractor.extract_urls(text)
      return nil if urls.blank?
      url = urls.first
      url = 'https://' + url unless url =~ /^https?:\/\//
      URI.parse(url)
      m = Link.new url: url
      m.validate_pender_result(false, true)
      if m.pender_error
        raise SecurityError if m.pender_error_code == PenderClient::ErrorCodes::UNSAFE
        nil
      else
        m.url
      end
    rescue URI::InvalidURIError
      nil
    end
  end

  def self.add_hashtags(text, pm)
    hashtags = Twitter::Extractor.extract_hashtags(text)
    return nil if hashtags.blank?

    # Only add team tags.
    TagText
      .joins('LEFT JOIN projects ON projects.team_id = tag_texts.team_id')
      .where('projects.id=? AND teamwide=? AND text IN (?)', pm.project_id, true, hashtags)
      .each do |tag|
        unless pm.annotations('tag').map(&:tag_text).include?(tag.text)
          Tag.create!(tag: tag, annotator: pm.user, annotated: pm)
        end
      end
  end

  def self.ban_user(message)
    uid = message['authorId']
    Rails.logger.info("[Smooch Bot] Banned user #{uid}")
    Rails.cache.write("smooch:banned:#{uid}", message.to_json)
  end

  def self.save_text_message(message)
    text = message['text']

    begin
      url = self.extract_url(text)
      if url.nil?
        pm = ProjectMedia.joins(:media).where('lower(quote) = ?', text.downcase).where('project_medias.project_id' => message['project_id']).last
        if pm.nil?
          pm = ProjectMedia.create!(project_id: message['project_id'], quote: text)
        end
      else
        pm = ProjectMedia.joins(:media).where('medias.url' => url, 'project_medias.project_id' => message['project_id']).last
        if pm.nil?
          pm = ProjectMedia.create!(project_id: message['project_id'], url: url)
          pm.embed = { description: text }.to_json if text != url
        elsif text != url
          Comment.create! annotated: pm, text: text, force_version: true
        end
      end

      self.add_hashtags(text, pm)

      pm
    rescue SecurityError
      self.ban_user(message)
      nil
    end
  end

  def self.save_image_message(message)
    open(message['mediaUrl']) do |f|
      text = message['text']

      data = f.read
      hash = Digest::MD5.hexdigest(data)
      filepath = File.join(Rails.root, 'tmp', "#{hash}.jpeg")
      File.atomic_write(filepath) { |file| file.write(data) }
      pm = ProjectMedia.joins(:media).where('medias.type' => 'UploadedImage', 'medias.file' => "#{hash}.jpeg", 'project_medias.project_id' => message['project_id']).last
      if pm.nil?
        m = UploadedImage.new
        File.open(filepath) do |f2|
          m.file = f2
        end
        m.save!
        pm = ProjectMedia.create!(project_id: message['project_id'], media: m)
        pm.embed = { description: text }.to_json unless text.blank?
      elsif !text.blank?
        Comment.create! annotated: pm, text: text, force_version: true
      end
      FileUtils.rm_f filepath

      self.add_hashtags(text, pm)

      pm
    end
  end

  def self.get_previous_final_status(pm)
    previous_final_status = nil
    begin
      finals = ::Workflow::Workflow.options(pm, 'verification_status').with_indifferent_access['statuses'].select{ |s| s['completed'].to_i == 1 }.collect{ |s| s['id'].gsub(/^not_true$/, 'false') }
      previous_final_statuses = []
      pm.last_verification_status_obj.get_field('verification_status_status').versions.each do |v|
        status = YAML.load(JSON.parse(v.object_after)['value']).to_s
        previous_final_statuses << status if finals.include?(status)
      end
      previous_final_status = previous_final_statuses[-2]
    rescue
      previous_final_status = nil
    end
    previous_final_status
  end

  def self.reply_to_smooch_users(pm_id, status)
    pm = ProjectMedia.where(id: pm_id).last
    unless pm.nil?
      previous_final_status = self.get_previous_final_status(pm)
      pm.get_annotations('smooch').find_each do |annotation|
        data = JSON.parse(annotation.load.get_field_value('smooch_data'))
        self.get_installation('smooch_app_id', data['app_id']) if self.config.blank?
        self.send_verification_results_to_user(data['authorId'], pm, status, data['language'], previous_final_status)
      end
    end
  end

  def self.reply_to_smooch_users_not_final(pm_id, status)
    pm = ProjectMedia.where(id: pm_id).last
    unless pm.nil?
      pm.get_annotations('smooch').find_each do |annotation|
        data = JSON.parse(annotation.load.get_field_value('smooch_data'))
        self.get_installation('smooch_app_id', data['app_id']) if self.config.blank?
        lang = data['language']
        status_label = self.get_status_label(pm, status, lang)
        response = ::Bot::Smooch.send_message_to_user(data['authorId'], I18n.t(:smooch_bot_not_final, locale: lang, status: status_label))
        self.save_smooch_response(response, pm)
      end
    end
  end

  def self.replicate_status_to_children(pm_id, status, uid, tid)
    pm = ProjectMedia.where(id: pm_id).last
    return if pm.nil?
    User.current = User.where(id: uid).last
    Team.current = Team.where(id: tid).last
    pm.source_relationships.joins('INNER JOIN users ON users.id = relationships.user_id').where("users.type != 'BotUser' OR users.type IS NULL").find_each do |relationship|
      target = relationship.target
      s = target.annotations.where(annotation_type: 'verification_status').last&.load
      next if s.nil? || s.status == status
      s.status = status
      s.save!
    end
    User.current = nil
    Team.current = nil
  end

  def self.cancel_reminder_job(uid)
    key = 'smooch:reminder:' + uid
    job_id = Rails.cache.read(key)
    unless job_id.nil?
      Sidekiq::Status.cancel(job_id)
      Rails.cache.delete(key)
    end
  end

  def self.send_verification_results_to_user(uid, pm, status, lang, previous_final_status = nil)
    self.cancel_reminder_job(uid)

    extra = {
      metadata: {
        id: pm.id
      }
    }
    status_label = self.get_status_label(pm, status, lang)
    params = { locale: lang, status: status_label, url: Bot::Smooch.embed_url(pm) }
    i18n_key = :smooch_bot_result
    unless previous_final_status.blank?
      i18n_key = :smooch_bot_result_changed
      params[:previous_status] = self.get_status_label(pm, previous_final_status, lang)
    end
    response = ::Bot::Smooch.send_message_to_user(uid, I18n.t(i18n_key, params), extra)
    self.save_smooch_response(response, pm)
    id = response&.message&.id
    Rails.cache.write('smooch:response:' + id, pm.id) unless id.blank?
    response
  end

  def self.get_parent(pm)
    Relationship.joins(:user).where(target_id: pm.id).where("users.type != 'BotUser' OR users.type IS NULL").last&.source
  end

  def self.get_meme(pm)
    pm = Bot::Smooch.get_parent(pm) || pm
    pm.get_annotations('memebuster').last&.load
  end

  def self.embed_url(pm)
    pm = Bot::Smooch.get_parent(pm) || pm
    pm.embed_url
  end

  def self.send_meme_to_user(uid, pm, lang)
    annotation = Bot::Smooch.get_meme(pm)
    return if annotation.nil? || annotation.get_field_value('memebuster_published_at').blank?
    meme = annotation.memebuster_png_path(false)
    Bot::Smooch.send_message_to_user(uid, I18n.t(:smooch_bot_meme, locale: lang, url: Bot::Smooch.embed_url(pm)), { type: 'image', mediaUrl: meme })
  end

  def self.save_smooch_response(response, pm)
    a = Dynamic.new
    a.annotated = pm
    a.annotation_type = 'smooch_response'
    a.disable_es_callbacks = true
    a.disable_update_status = true
    a.skip_notifications = true
    a.skip_check_ability = true
    a.set_fields = { smooch_response_data: response.to_json }.to_json
    a.save!
  end

  def self.send_meme_from_parent(parent_id, child_id)
    parent = ProjectMedia.where(id: parent_id).last
    child = ProjectMedia.where(id: child_id).last
    if parent && child
      annotation = parent.get_annotations('memebuster').last&.load
      unless annotation.nil?
        meme = annotation.memebuster_png_path(true)
        Bot::Smooch.send_meme(parent, child, meme)
      end
    end
  end

  def self.send_meme(pm, pm2, meme)
    pm2.get_annotations('smooch').find_each do |a|
      data = JSON.parse(a.load.get_field_value('smooch_data'))
      self.get_installation('smooch_app_id', data['app_id']) if self.config.blank?
      smooch_response = ::Bot::Smooch.send_message_to_user(data['authorId'], I18n.t(:smooch_bot_meme, locale: data['language'], url: Bot::Smooch.embed_url(pm)), { type: 'image', mediaUrl: meme })
      self.save_smooch_response(smooch_response, pm2)
    end
  end

  def self.send_meme_to_smooch_users(annotation_id)
    annotation = Dynamic.where(id: annotation_id).last
    pm = annotation&.annotated
    return if pm.nil?
    meme = annotation.memebuster_png_path(true)
    self.send_meme(pm, pm, meme)
    pm.source_relationships.joins('INNER JOIN users ON users.id = relationships.user_id').where("users.type != 'BotUser' OR users.type IS NULL").find_each do |relationship|
      pm2 = relationship.target
      self.send_meme(pm, pm2, meme)
    end
    annotation.set_fields = { memebuster_published_at: Time.now }.to_json
    annotation.save!
  end
end
