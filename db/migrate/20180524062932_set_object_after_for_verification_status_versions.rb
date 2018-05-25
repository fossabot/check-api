class SetObjectAfterForVerificationStatusVersions < ActiveRecord::Migration
  def change
    PaperTrail::Version.where(event_type: 'update_dynamicannotationfield').find_each do |version|
      item = DynamicAnnotation::Field.where(id: version.item_id).last
      if !item.nil? && version.item_type == 'DynamicAnnotation::Field' && item.field_name == 'verification_status_status'
        object_after = item.as_json.merge(JSON.parse(version.object_after)).to_json
        version.update_attributes({ object_after: object_after })
        puts "Saved version #{version.id}"
      end
    end
  end
end
