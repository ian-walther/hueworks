defmodule Hueworks.HomeAssistant.Export.Publisher do
  @moduledoc false

  alias Hueworks.HomeAssistant.Export.Entities
  alias Hueworks.HomeAssistant.Export.Messages
  alias Hueworks.PublishedIdentity
  alias Hueworks.Repo
  alias Hueworks.Schemas.{PresenceInput, Area, Scene}

  def publish_scene_payloads(publish_fun, %Scene{} = scene, config)
      when is_function(publish_fun, 3) do
    discovery = Messages.discovery_topic(scene.id, config.discovery_prefix)
    attributes = Messages.attributes_topic(scene.id)

    :ok =
      publish_fun.(discovery, Jason.encode!(Messages.discovery_payload(scene, config)),
        retain: true
      )

    publish_fun.(attributes, Jason.encode!(Messages.scene_attributes_payload(scene)),
      retain: true
    )
  end

  def unpublish_scene_payloads(publish_fun, scene_id, config)
      when is_function(publish_fun, 3) and is_integer(scene_id) do
    discovery = Messages.discovery_topic(scene_id, config.discovery_prefix)
    attributes = Messages.attributes_topic(scene_id)

    :ok = publish_fun.(discovery, "", retain: true)
    publish_fun.(attributes, "", retain: true)
  end

  def sync_entity_payloads(publish_fun, _kind, nil, _config) when is_function(publish_fun, 3),
    do: :ok

  def sync_entity_payloads(publish_fun, kind, entity, config)
      when is_function(publish_fun, 3) and kind in [:light, :group] and is_map(entity) do
    case Messages.entity_export_mode(entity) do
      :switch ->
        :ok = publish_switch_payloads(publish_fun, kind, entity, config)
        :ok = unpublish_light_payloads(publish_fun, kind, entity.id, config)

      :light ->
        :ok = publish_light_payloads(publish_fun, kind, entity, config)
        :ok = unpublish_switch_payloads(publish_fun, kind, entity.id, config)

      _ ->
        :ok = unpublish_entity_payloads(publish_fun, kind, entity.id, config)
    end
  end

  def publish_area_select_payloads(publish_fun, %Area{} = area, config)
      when is_function(publish_fun, 3) do
    scenes = Entities.list_exportable_scenes_for_area(area.id)

    if scenes == [] do
      unpublish_area_select_payloads(publish_fun, area, config)
    else
      discovery =
        Messages.area_select_discovery_topic(
          PublishedIdentity.fetch!(area, :ha_scene_select_identifier),
          config.discovery_prefix
        )

      state_topic = Messages.area_select_state_topic(area.id)
      attributes_topic = Messages.area_select_attributes_topic(area.id)

      :ok =
        publish_fun.(
          discovery,
          Jason.encode!(Messages.area_select_discovery_payload(area, scenes, config)),
          retain: true
        )

      :ok =
        publish_fun.(
          attributes_topic,
          Jason.encode!(Messages.area_select_attributes_payload(area, scenes)),
          retain: true
        )

      publish_fun.(state_topic, Messages.area_select_state_payload(area.id, scenes), retain: true)
    end
  end

  def publish_area_select_payloads(publish_fun, area_id, config)
      when is_function(publish_fun, 3) and is_integer(area_id) do
    case Repo.get(Area, area_id) do
      %Area{} = area -> publish_area_select_payloads(publish_fun, area, config)
      nil -> :ok
    end
  end

  def unpublish_area_select_payloads(publish_fun, %Area{} = area, config)
      when is_function(publish_fun, 3) do
    unpublish_area_select_payloads(
      publish_fun,
      area.id,
      PublishedIdentity.fetch!(area, :ha_scene_select_identifier),
      config
    )
  end

  def unpublish_area_select_payloads(publish_fun, area_id, identifier, config)
      when is_function(publish_fun, 3) and is_integer(area_id) and is_binary(identifier) do
    discovery = Messages.area_select_discovery_topic(identifier, config.discovery_prefix)
    attributes = Messages.area_select_attributes_topic(area_id)
    state = Messages.area_select_state_topic(area_id)

    :ok = publish_fun.(discovery, "", retain: true)
    :ok = publish_fun.(attributes, "", retain: true)
    publish_fun.(state, "Manual", retain: true)
  end

  def publish_presence_input_payloads(publish_fun, nil, _config)
      when is_function(publish_fun, 3),
      do: :ok

  def publish_presence_input_payloads(publish_fun, %PresenceInput{} = input, config)
      when is_function(publish_fun, 3) do
    discovery = Messages.presence_input_discovery_topic(input.id, config.discovery_prefix)
    attributes = Messages.presence_input_attributes_topic(input.id)
    state = Messages.presence_input_state_topic(input.id)

    :ok =
      publish_fun.(
        discovery,
        Jason.encode!(Messages.presence_input_discovery_payload(input, config)),
        retain: true
      )

    :ok =
      publish_fun.(
        attributes,
        Jason.encode!(Messages.presence_input_attributes_payload(input)),
        retain: true
      )

    publish_fun.(state, Messages.presence_input_state_payload(input), retain: true)
  end

  def unpublish_presence_input_payloads(publish_fun, input_id, config)
      when is_function(publish_fun, 3) and is_integer(input_id) do
    :ok =
      publish_fun.(
        Messages.presence_input_discovery_topic(input_id, config.discovery_prefix),
        "",
        retain: true
      )

    :ok = publish_fun.(Messages.presence_input_attributes_topic(input_id), "", retain: true)
    publish_fun.(Messages.presence_input_state_topic(input_id), "None", retain: true)
  end

  def publish_optimistic_entity_state(publish_fun, kind, entity, state)
      when is_function(publish_fun, 3) and kind in [:light, :group] and is_map(entity) and
             is_map(state) do
    case Messages.entity_export_mode(entity) do
      :switch ->
        publish_fun.(
          Messages.switch_state_topic(kind, entity.id),
          Messages.switch_state_payload(state),
          retain: true
        )

      :light ->
        publish_fun.(
          Messages.light_state_topic(kind, entity.id),
          Jason.encode!(Messages.light_state_payload(entity, state)),
          retain: true
        )

      _ ->
        :ok
    end
  end

  def unpublish_entity_payloads(publish_fun, kind, id, config)
      when is_function(publish_fun, 3) and kind in [:light, :group] and is_integer(id) do
    :ok = unpublish_switch_payloads(publish_fun, kind, id, config)
    :ok = unpublish_light_payloads(publish_fun, kind, id, config)
    publish_fun.(Messages.entity_attributes_topic(kind, id), "", retain: true)
  end

  defp publish_switch_payloads(publish_fun, kind, entity, config)
       when is_function(publish_fun, 3) and kind in [:light, :group] and is_map(entity) do
    discovery = Messages.switch_discovery_topic(kind, entity.id, config.discovery_prefix)
    attributes = Messages.entity_attributes_topic(kind, entity.id)
    state_topic = Messages.switch_state_topic(kind, entity.id)

    :ok =
      publish_fun.(
        discovery,
        Jason.encode!(Messages.switch_discovery_payload(kind, entity, config)),
        retain: true
      )

    :ok =
      publish_fun.(
        attributes,
        Jason.encode!(Messages.entity_attributes_payload(kind, entity)),
        retain: true
      )

    publish_fun.(state_topic, Messages.switch_state_payload(kind, entity.id), retain: true)
  end

  defp publish_light_payloads(publish_fun, kind, entity, config)
       when is_function(publish_fun, 3) and kind in [:light, :group] and is_map(entity) do
    discovery = Messages.light_discovery_topic(kind, entity.id, config.discovery_prefix)
    attributes = Messages.entity_attributes_topic(kind, entity.id)
    state_topic = Messages.light_state_topic(kind, entity.id)

    :ok =
      publish_fun.(
        discovery,
        Jason.encode!(Messages.light_discovery_payload(kind, entity, config)),
        retain: true
      )

    :ok =
      publish_fun.(
        attributes,
        Jason.encode!(Messages.entity_attributes_payload(kind, entity)),
        retain: true
      )

    publish_fun.(state_topic, Jason.encode!(Messages.light_state_payload(kind, entity)),
      retain: true
    )
  end

  defp unpublish_switch_payloads(publish_fun, kind, id, config)
       when is_function(publish_fun, 3) and kind in [:light, :group] and is_integer(id) do
    :ok =
      publish_fun.(
        Messages.switch_discovery_topic(kind, id, config.discovery_prefix),
        "",
        retain: true
      )

    publish_fun.(Messages.switch_state_topic(kind, id), "None", retain: true)
  end

  defp unpublish_light_payloads(publish_fun, kind, id, config)
       when is_function(publish_fun, 3) and kind in [:light, :group] and is_integer(id) do
    :ok =
      publish_fun.(
        Messages.light_discovery_topic(kind, id, config.discovery_prefix),
        "",
        retain: true
      )

    publish_fun.(
      Messages.light_state_topic(kind, id),
      Jason.encode!(%{"state" => nil}),
      retain: true
    )
  end
end
