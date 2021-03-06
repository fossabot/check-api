require 'active_support/concern'

module ProjectMediaCreators
  extend ActiveSupport::Concern
  
  private

  def set_project_source
    return if self.project.team.is_being_copied
    self.create_project_source
  end

  def create_auto_tasks
    return if self.project.team.is_being_copied
    self.set_tasks_responses ||= {}
    tasks = self.project.nil? ? [] : self.project.auto_tasks
    created = []
    tasks.each do |task|
      t = Task.new
      t.label = task.label
      t.type = task.task_type
      t.required = task.required
      t.description = task.description
      t.team_task_id = task.id
      t.options = task.options unless task.options.blank?
      t.annotator = User.current
      t.annotated = self
      t.skip_check_ability = true
      t.skip_notifications = true
      t.disable_update_status = true if t.respond_to?(:disable_update_status)
      t.save!
      created << t
      # set auto-response
      self.set_jsonld_response(task) unless task.mapping.blank?
    end
    self.respond_to_auto_tasks(created)
  end

  def create_reverse_image_annotation
    return if self.project.team.is_being_copied
    picture = self.media.picture
    unless picture.blank?
      d = Dynamic.new
      d.skip_check_ability = true
      d.skip_notifications = true
      d.annotation_type = 'reverse_image'
      d.annotator = Bot::Bot.where(name: 'Check Bot').last
      d.annotated = self
      d.disable_es_callbacks = Rails.env.to_s == 'test'
      d.set_fields = { reverse_image_path: picture }.to_json
      d.save!
    end
  end

  def create_annotation
    unless self.set_annotation.blank?
      params = JSON.parse(self.set_annotation)
      annotation = Dynamic.new
      annotation.annotated = self
      annotation.annotation_type = params['annotation_type']
      annotation.set_fields = params['set_fields']
      annotation.disable_es_callbacks = Rails.env.to_s == 'test'
      annotation.skip_notifications = true
      annotation.save!
    end
  end

  def set_quote_embed
    self.embed = ({ title: self.media.quote }.to_json) unless self.media.quote.blank?
    self.embed = ({ title: File.basename(self.media.file.path) }.to_json) unless self.media.file.blank?
  end

  protected

  def create_image
    m = UploadedImage.new
    m.file = self.file
    m.save!
    m
  end

  def create_claim
    m = Claim.new
    m.quote = self.quote
    m.quote_attributions = self.quote_attributions
    m.save!
    m
  end

  def create_link
    m = Link.new
    m.url = self.url
    # call m.valid? to get normalized URL before caling 'find_or_create_by'
    m.valid?
    m = Link.find_or_create_by(url: m.url)
    m
  end

  def create_media
    m = nil
    if !self.file.blank?
      m = self.create_image
    elsif !self.quote.blank?
      m = self.create_claim
    else
      m = self.create_link
    end
    m
  end

  def set_jsonld_response(task)
    jsonld = self.embed['raw']['json+ld'] if self.embed.has_key?('raw')
    unless jsonld.nil?
      value = self.get_response_value(jsonld, task)
      self.set_tasks_responses[Task.slug(task['label'])] = value unless value.blank?
    end
  end

  def get_response_value(jsonld, task)
    require 'jsonpath'
    mapping = task['mapping']
    self.mapping_suggestions(task, mapping['type']).each do |name|
      return self.send(name, jsonld, mapping) if self.respond_to?(name)
    end
    data = mapping_value(jsonld, mapping)
    (!data.blank? && data.kind_of?(String)) ? mapping['prefix'].gsub(/\s+$/, '') + ' ' + data : ''
  end

  def mapping_value(jsonld, mapping)
    begin
      value = JsonPath.new(mapping['match']).first(jsonld)
    rescue
      value = nil
    end
    value
  end

  def mapping_suggestions(task, mapping_type)
    [
      "mapping_#{Task.slug(task['label'])}",
      "mapping_#{task['type']}_#{mapping_type}",
      "mapping_#{task['type']}",
    ]
  end

  def respond_to_auto_tasks(tasks)
    # set_tasks_responses = { task_slug (string) => response (string) }
    responses = self.set_tasks_responses.to_h
    tasks.each do |task|
      if responses.has_key?(task.slug)
        task = Task.find(task.id)
        type = "task_response_#{task.type}"
        fields = {
          "response_#{task.type}" => responses[task.slug]
        }
        task.response = { annotation_type: type, set_fields: fields.to_json }.to_json
        task.save!
      end
    end
  end

  def create_project_source
    a = self.media.account
    source = Account.create_for_source(a.url, nil, false, self.disable_es_callbacks).source unless a.nil?
    if source.nil?
      cs = ClaimSource.where(media_id: self.media_id).last
      source = cs.source unless cs.nil?
    end
    unless source.nil?
      unless ProjectSource.where(project_id: self.project_id, source_id: source.id).exists?
        ps = ProjectSource.new
        ps.project_id = self.project_id
        ps.source_id = source.id
        ps.disable_es_callbacks = self.disable_es_callbacks
        ps.skip_check_ability = true
        ps.save!
      end
    end
  end

  def create_relationship(type = Relationship.default_type)
    unless self.related_to_id.nil?
      related = ProjectMedia.where(id: self.related_to_id).last
      if !related.nil? && related.project_id == self.project_id
        r = Relationship.new
        r.skip_check_ability = true
        r.relationship_type = type
        r.source_id = related.id
        r.target_id = self.id
        r.save!
      else
        raise 'Could not create related item'
      end
    end
  end
end
