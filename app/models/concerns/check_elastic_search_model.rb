module CheckElasticSearchModel
  extend ActiveSupport::Concern

  included do
    include ActiveModel::Validations
    include ActiveModel::Validations::Callbacks
    include Elasticsearch::Persistence::Model

    index_name CheckElasticSearchModel.get_index_name

    settings analysis: {
      char_filter: {
        space_hashtags: {
          type: 'mapping',
          mappings: ['#=>|#']
        }
      },
      filter: {
        hashtag_as_alphanum: {
          type: 'word_delimiter',
          type_table: ['# => ALPHANUM', '@ => ALPHANUM']
        }
      },
      analyzer: {
        check: {
          type: 'custom',
          char_filter: 'space_hashtags',
          tokenizer: 'whitespace',
          filter: ['lowercase', 'hashtag_as_alphanum', 'asciifolding','icu_normalizer','arabic_normalization']
        }
      }
    }

    attribute :annotation_type, String
    before_validation :set_type
  end

  def save!(options = {})
    raise 'Sorry, this is not valid' unless self.save(options)
  end

  def self.get_index_name
    CONFIG['elasticsearch_index'].blank? ? [Rails.application.engine_name, Rails.env, 'annotations'].join('_') : CONFIG['elasticsearch_index']
  end

  private

  def set_type
    self.annotation_type ||= self.class.name.parameterize
  end

  module ClassMethods
    def create_index
      client = self.gateway.client
      index_name = self.index_name
      settings = []
      mappings = []
      [MediaSearch, CommentSearch, TagSearch, DynamicSearch].each do |klass|
        settings << klass.settings.to_hash
        mappings << klass.mappings.to_hash
      end
      settings = settings.reduce(:merge)
      mappings = mappings.reduce(:merge)
      client.indices.create index: index_name, body: { settings: settings.to_hash, mappings: mappings.to_hash }
    end

    def delete_index
      client = self.gateway.client
      index_name = self.index_name
      if client.indices.exists? index: index_name
        client.indices.delete index: index_name
      end
    end

    def reindex_es_data(mapping_keys = nil)
      old_index = CONFIG['old_elasticsearch_index']
      unless old_index.blank?
        mapping_keys = [MediaSearch, CommentSearch, TagSearch, DynamicSearch] if mapping_keys.nil?
        MediaSearch.delete_index
        MediaSearch.create_index
        n = 0
        mapping_keys.each do |klass|
          Rails.logger.info "[ES MIGRATION] Migrating #{klass.name.parameterize} to #{CONFIG['elasticsearch_index']}"
          # Load data from old index
          url = "http://#{CONFIG['elasticsearch_host']}:#{CONFIG['elasticsearch_port']}"
          repository = Elasticsearch::Persistence::Repository.new url: url
          repository.type = klass.name.underscore
          repository.klass = klass
          repository.index = CONFIG['old_elasticsearch_index']
          results = repository.search(query: { match: { annotation_type: klass.name.parameterize } }, size: 10000)
          # Save data in new index
          results.each_with_hit do |obj, hit|
            n += 1
            begin
              options = {}
              options = {parent: hit._parent} unless hit._parent.nil?
              obj.id = hit._id
              obj.save!(options)
              Rails.logger.info "[ES MIGRATION] Migrated #{klass.name} ##{n}"
            rescue StandardError => e
              Rails.logger.error "[ES MIGRATION] Could not migrate this item: #{obj.inspect}: #{e.message}"
            end
          end
        end
      end
      Rails.logger.info "Migration is finished! #{n} items were migrated."
    end

    def all_sorted(order = 'asc', field = 'created_at')
      type = self.name.parameterize
      query = type === 'annotation' ? { match_all: {} } : { bool: { must: [{ match: { annotation_type: type } }] } }
      self.search(query: query, sort: [{ field => { order: order }}, '_score'], size: 10000).results
    end

    def length
      type = self.name.parameterize
      self.count({ query: { bool: { must: [{ match: { annotation_type: type } }] } } })
    end
  end
end
