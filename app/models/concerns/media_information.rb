require 'active_support/concern'

module MediaInformation
  extend ActiveSupport::Concern

  def set_information
    info = self.parse_information
    
    unless self.information_blank? 
      em_context = self.get_embed_context
      em_none = self.get_embed_regardless_context
      
      em = if em_context.nil? and em_none.nil?
             self.set_information_for_null_context 
           elsif self.project.nil?
             self.set_information_for_null_project(em_none)
           else
             self.set_information_for_context_or_project(em_context, em_none)
           end
      
      self.set_information_for_embed(em, info)
      self.information = {}.to_json
    end
  end

  protected

  def information_blank?
    self.parse_information.all? { |_k, v| v.blank? }
  end

  def get_embed_context
    self.annotations('embed', self.project).last unless self.project.nil?
  end

  def get_embed_regardless_context
    self.annotations('embed', 'none').last
  end

  def parse_information
    self.information.blank? ? {} : JSON.parse(self.information)
  end

  def set_information_for_null_context
    self.create_new_embed
  end

  def set_information_for_null_project(em_none)
    em_none.nil? ? self.create_new_embed : em_none
  end

  def set_information_for_context_or_project(em_context, em_none)
    em = em_context unless em_context.nil?
    if em.nil?
      em = em_none.nil? ? self.create_new_embed : em_none
    end
    if em.context.nil?
      em.context = self.project
      em.id = nil
    end
    em
  end

  def set_information_for_embed(em, info)
    info.each{ |k, v| em.send("#{k}=", v) if em.respond_to?(k) and !v.blank? }
    em.save!
  end
end
