RelationshipsType = GraphQL::ObjectType.define do
  name 'Relationships'
  description 'The sources and targets relationships of the project media'
  interfaces [NodeIdentification.interface]
  global_id_field :id
  
  field :targets_count, types.Int

  connection :sources, -> { RelationshipsSourceType.connection_type } do
    resolve ->(obj, args, _ctx) {
      project_media = ProjectMedia.find(obj.project_media_id)
      project_media.target_relationships.includes(:source).collect do |relationship|
        OpenStruct.new({
          id: relationship.id,
          relationship_id: relationship.id,
          source: relationship.source,
          type: relationship.relationship_type.to_json,
          siblings: relationship.siblings
        })
      end
    }
  end

  connection :targets, -> { RelationshipsTargetType.connection_type } do
    resolve ->(obj, args, _ctx) {
      project_media = ProjectMedia.find(obj.project_media_id)
      Relationship.targets_grouped_by_type(project_media).collect{ |x| OpenStruct.new(x) }
    }
  end
end
