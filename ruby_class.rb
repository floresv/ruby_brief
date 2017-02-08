# encoding: utf-8
# Summary: Ruby controller base
class RubyController < ApplicationController
  # entity states
  @@status = %w(pending associated deprecated)

  before_action :check_key

  # Summary: servicio para cargar entidades segun paginacion, origen y estado
  #
  # Params:
  # Return success: JSON de entidades
  # Return error: JSON status con mensaje de error
  def index
    begin
      offset, limit, parsed_sources, is_internal_flow, state = parse_params(params)

      entities = (entity_states state)
                .includes(:typeable,
                typeable: :association_entries,
                typeable: {association_entries: :association_members},
                typeable: {association_entries: {association_members: :associable}})
                .offset(offset)
                .order(:admission_at, :id)

      first_types = entities.first_type.map(&:typeable)
      entities = entities.where.not(typeable_id: first_types.select!{|d| !parsed_sources.include? d.source_id})
      entities = entities.second_type if is_internal_flow
      entities = entities.limit(limit) unless limit.nil?

      second_types = is_internal_flow ? entities.second_type : []
      first_types = entities.first_type.map(&:typeable)
      first_types.select!{|d| parsed_sources.include? d.source_id} unless parsed_sources.nil?

      states = Entity.not_associated.first_type.joins('LEFT JOIN first_types ON first_types.id = entities.typeable_id')
      states = states.where('first_types.source_id' => parsed_sources) unless parsed_sources.nil?
      state_count = states.group('entities.state').count
      second_types_count = Entity.not_associated.second_type.group('state').count
      state_count.merge!(second_types_count){ |k, a, b| a + b } if is_internal_flow

      associations_count = Association.associated.created_today.count

      render json: Hash[status: true,
                        entities: json_entities([first_types.collect! {|d| d.entity}, second_types]),
                        state_count: state_count,
                        associated_count: associations_count]
    rescue Exception => e
      notify_exception e
      return error('Entity index exception', e)
    end
  end
end
