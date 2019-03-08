require 'active_support/concern'
require 'google_drive'

module TeamImport
  extend ActiveSupport::Concern

  module ClassMethods

    def spreadsheet_id(url)
      pattern = /https:\/\/docs\.google\.com\/spreadsheets\/d\/([a-zA-Z0-9\-\_]+)/
      match = url.match(pattern)
      match ? match[1] : nil
    end

    def import_spreadsheet_in_background(spreadsheet_url, team_id, user_id)
      spreadsheet_id = self.spreadsheet_id(spreadsheet_url)
      error = { message: I18n.t('team_import.invalid_google_spreadsheet_url', spreadsheet_url: spreadsheet_url), code: 'INVALID_VALUE'}
      raise error.to_json unless spreadsheet_id
      TeamImportWorker.perform_async(team_id, spreadsheet_id, user_id)
    end

    def notify_airbrake(exception, extra_info = {})
      exception = RuntimeError.new(exception.to_s) unless exception.is_a?(Exception)
      Airbrake.notify(exception, parameters: { label: 'Team Import' }.merge(extra_info)) if Airbrake.configuration.api_key
    end

  end

  included do
    FLEXIBLE_COLS = 9

    notifies_pusher on: :touch,
                    event: proc { |t| t.import_status },
                    targets: proc { |t| [t] },
                    if: proc { |t| !t.import_status.blank? },
                    data: proc { |t| {message: t.import_status}.to_json }

    attr_accessor :spreadsheet, :import_status

    def import_spreadsheet(spreadsheet_id, title = '', user_id)
      @result = {}
      return unless get_spreadsheet(spreadsheet_id)

      user = User.find_by_id(user_id)
      Team.notify_airbrake('User not found on database', { team: self.slug, user_id: user_id, spreadsheet_url: self.spreadsheet.human_url }); return if !user

      worksheet = title.blank? ? self.spreadsheet.worksheets[0] : self.spreadsheet.worksheet_by_title(title)
      start_time = Time.now
      Rails.logger.info "[Team Import] Importing spreadsheet #{spreadsheet_id} to team #{self.slug} (requested by user #{user.login})"
      RequestStore.store[:skip_notifications] = true
      self.update_import_status('start')
      get_flexible_columns(worksheet)

      save_project_medias(worksheet, user)
      save_annotations(user)
      save_statuses

      update_worksheet(worksheet)
      Rails.logger.info "[Team Import] Finished import of spreadsheet #{spreadsheet_id} to team #{self.slug} in #{Time.now - start_time} seconds"
      AdminMailer.delay.notify_import_completed(user.email, worksheet.human_url) unless user.email.blank? || worksheet.nil?
      RequestStore.store[:skip_notifications] = false
      @result
    end

    def callbacks(collection, user, methods = [:save, :create])
      User.current = user
      collection.each do |c|
        c.skip_notifications = true
        methods.each do |method|
          c.run_callbacks(method)
        end
      end
      User.current = nil
    end

    def get_spreadsheet(id = '')
      begin
        @session = GoogleDrive::Session.from_service_account_key(CONFIG['google_credentials_path'])
        self.spreadsheet = @session.spreadsheet_by_key(id) if @session
      rescue Signet::AuthorizationError, Google::Apis::ClientError, StandardError => e
        Team.notify_airbrake(e, { team: self.slug, spreadsheet_id: id, message: e.message })
      end
      self.spreadsheet
    end

    def save_project_medias(worksheet, user)
      begin
        for row in 2..worksheet.num_rows
          @result[row] = { messages: [] }
          import_row(worksheet, row)
        end

        project_medias = []
        @result.values.each do |value|
          project_medias << value[:pm] if value[:pm] && value[:pm].id.nil?
        end
        save_objects(ProjectMedia, project_medias, user)
      rescue Exception => e
        Team.notify_airbrake(e, { team: self.slug, user_id: user.id, spreadsheet_url: self.spreadsheet.human_url, action: 'save_project_medias' })
      end
    end

    def save_annotations(user)
      begin
        annotations = []
        @result.values.each do |value|
          next if value[:pm].nil? || value[:pm].id.nil?
          value[:annotations].each do |a|
            a.annotated = value[:pm]
            annotations << a
          end
        end
        save_objects(Annotation, annotations, user)
      rescue Exception => e
        Team.notify_airbrake(e, { team: self.slug, user_id: user.id, spreadsheet_url: self.spreadsheet.human_url, action: 'save_annotations' })
      end
    end

    def save_statuses
      begin
        @result.values.each do |value|
          next if value[:pm].nil? || value[:pm].id.nil?
          update_status(value[:pm], value[:status_changes])
        end
      rescue Exception => e
        Team.notify_airbrake('Could not update statuses', { team: self.slug, spreadsheet_url: self.spreadsheet.human_url, action: 'save_statuses' })
      end
    end

    def import_row(worksheet, row)
      data = {
        item: worksheet[row, 2],
        user: worksheet[row, 3],
        projects: worksheet[row, 4],
        assigned_to: worksheet[row, 5],
        tags: worksheet[row, 6],
        status: worksheet[row, 7]
      }

      user = get_user(data[:user], row)
      projects = get_projects(data[:projects], row)
      return if user.nil?
      projects.each do |project|
        pm = create_item(project, data[:item], user.id, row)
        if pm
          @result[row][:pm] = pm
          add_status_and_assign_to_user(pm, data[:status], data[:assigned_to], row)
          add_tags(pm, data[:tags], row, user)
          add_notes(pm, worksheet, row, user)
          add_tasks_answers(pm, worksheet, row)
        end
      end
    end

    def verify_duplicated_link(url, row)
      duplicated = @result.each_pair.find {|k, v| v[:link] && v[:link] == url }
      if duplicated
        @result[row][:messages] << I18n.t("team_import.duplicated_url", row: duplicated[0])
      else
        @result[row][:link] = url
      end
      duplicated
    end

    def create_item(project, item, user_id, row)
      media = get_item(item, project)
      return media[:project_media] unless media[:project_media].nil?
      url = media.dig(:params, :url)
      return if verify_duplicated_link(url, row)
      pm = ProjectMedia.new({project_id: project, user_id: user_id}.merge(media[:params]))
      begin
        unless pm.valid?
          @result[row][:messages] << pm.errors.full_messages
          return
        end
      rescue StandardError => e
        message = JSON.parse(e.message)
        pm = (message['code'] == 'ERR_OBJECT_EXISTS') ? ProjectMedia.find_by_id(message.dig('data', 'id')) : nil
      end
      pm
    end

    def update_worksheet(worksheet)
      @result.each_pair do |row, value|
        value[:messages].unshift(value[:pm].full_url) if value[:pm] && value[:pm].id
        value[:messages].unshift(I18n.t("team_import.cannot_create_project_media")) if value[:pm] && !value[:pm].id
        worksheet[row, 1] = value[:messages].join(', ')
        worksheet.save if row == worksheet.num_rows
      end
    end

    protected

    def get_user(user, row, column = 'user', pm_user = nil)
      @result[row][:messages] << I18n.t("team_import.blank_#{column}") and return if user.blank?
      pattern = Regexp.new(CONFIG['checkdesk_client'] + "/check\/user\/([0-9]+)")
      if (match = pattern.match(user))
        u = User.find_by_id(match[1].to_i)
      else
        u = User.find_by_email(user) || pm_user || self.owners('owner').first
      end
      @result[row][:messages] << I18n.t("team_import.invalid_#{column}", user: user) if u.nil?
      u
    end

    def get_projects(projects, row = nil)
      projects = projects.split(',').map { |p| p.strip }
      @result[row][:messages] << I18n.t("team_import.blank_project") and return projects if projects.empty?
      pattern = Regexp.new(CONFIG['checkdesk_client'] + "/#{self.slug}\/project\/([0-9]+)")
      ids = []
      projects.each do |p|
        if (match = pattern.match(p))
          ids << match[1].to_i
        else
          @result[row][:messages] << I18n.t('team_import.invalid_project', team: self.slug, project: p) if @result
        end
      end
      ids
    end

    def get_item(item, project)
      params =
        begin
          uri = URI.parse(URI.encode(item))
          uri.host.nil? ? {quote: item} : {url: item}
        rescue
          {quote: item}
        end
      pm = ProjectMedia.joins(:media).where('medias.type' => 'Link', 'medias.url' => params[:url], 'project_id' => project).first if params[:url]
      {params: params, project_media: pm}
    end

    def get_flexible_columns(worksheet)
       @notes_cols = []
       @tasks = {}
       for col in FLEXIBLE_COLS..worksheet.num_cols
         col_title = worksheet[1, col]
         if col_title == 'Item note'
           @notes_cols << col
         else
           @tasks[col] = Task.slug(col_title)
         end
      end
    end

    def add_tags(pm, tags, row, pm_user)
      @result[row][:annotations] ||= []
      return if tags.blank?
      tags = tags.split(',').map { |t| t.strip }.reject(&:blank?)
      ids = Tag.where(annotation_type: 'tag', annotated_type: 'ProjectMedia', annotated_id: pm.id).map(&:tag)
      pm_tags = TagText.where(id: ids).map(&:text)
      tags.each do |t|
        unless pm_tags.include?(t)
          tag = Tag.new(tag: t, annotator: pm_user)
          @result[row][:annotations] << tag
        end
      end
    end

    def add_notes(pm, worksheet, row, pm_user)
      annotator = worksheet[row, 8]
      @result[row][:annotations] ||= []
      @notes_cols.each do |col|
        note = worksheet[row, col]
        next if note.blank?
        annotator_user = annotator.blank? ? pm_user : get_user(annotator, row, 'annotator')
        @result[row][:annotations] << Comment.new(annotation_type: 'comment', annotator: annotator_user, data: { text: note }.with_indifferent_access) if annotator_user
      end
    end

    def add_tasks_answers(pm, worksheet, row)
      tasks_responses = {}
      @tasks.each_pair do |col, slug|
        answer = worksheet[row, col]
        tasks_responses[slug] = answer unless answer.blank?
      end
      pm.set_tasks_responses = tasks_responses.with_indifferent_access
    end

    def add_status_and_assign_to_user(pm, status, assigned_to, row)
      user = get_user(assigned_to, row, 'assignee') unless assigned_to.blank?
      changes = {}
      if Workflow::Workflow.options(pm, pm.default_project_media_status_type)['statuses'].find { |s| s['id'] == status}.nil?
        @result[row][:messages] << I18n.t('team_import.invalid_status', status: status) unless status.blank?
      else
        changes[:status] = status
      end
      changes[:assigned_to_ids] = user.id if user
      @result[row][:status_changes] = changes
    end

    def save_objects(klass, collection, pm_user)
      begin
        ActiveRecord::Base.transaction do
          klass.import collection
          callbacks(collection, pm_user)
        end
      rescue StandardError => e
        Team.notify_airbrake(e, { team: self.slug, spreadsheet_url: self.spreadsheet.human_url, imported_class: klass, action: 'save_objects' })
      end
    end

    def update_status(pm, changes)
      return if pm.nil? || changes.nil? || changes.empty?
      begin
        status = Dynamic.where(annotation_type: pm.default_project_media_status_type, annotated_type: pm.class.name, annotated_id: pm.id).first
        status.update_attributes(changes)
      rescue StandardError => e
        Team.notify_airbrake(e, { team: self.slug, spreadsheet_url: self.spreadsheet.human_url, project_media: pm.id, imported_class: 'Status', status_changes: changes, action: 'update_status' })
      end
    end

    def update_status(pm, changes)
      return if pm.nil? || changes.nil? || changes.empty?
      status = pm.last_status_obj
      status.update_attributes(changes)
    end

    def update_import_status(status)
      self.import_status = "spreadsheet_import_#{status}"
      self.touch
    end
  end

end
