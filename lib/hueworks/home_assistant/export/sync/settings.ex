defmodule Hueworks.HomeAssistant.Export.Sync.Settings do
  @moduledoc false

  alias Hueworks.AppSettings
  alias Hueworks.Circadian.Timing
  alias Hueworks.HomeAssistant.Export.Config
  alias Hueworks.HomeAssistant.Export.Publisher

  def publish_all(publish_fun, session, config)
      when is_function(publish_fun, 3) and is_binary(session) do
    if Config.export_enabled?(config) do
      settings = AppSettings.get_global()

      Enum.each(Timing.window_fields(), fn field ->
        :ok =
          Publisher.publish_setting_payloads(
            publish_fun,
            field,
            Map.fetch!(settings, field),
            session,
            config
          )
      end)
    end

    :ok
  end

  def publish_states(publish_fun, fields, config)
      when is_function(publish_fun, 3) and is_list(fields) do
    if Config.export_enabled?(config) do
      settings = AppSettings.get_global()

      Enum.each(fields, fn field ->
        :ok = Publisher.publish_setting_state(publish_fun, field, Map.fetch!(settings, field))
      end)
    end

    :ok
  end

  def unpublish_all(publish_fun, config) when is_function(publish_fun, 3) do
    Enum.each(Timing.window_fields(), fn field ->
      :ok = Publisher.unpublish_setting_payloads(publish_fun, field, config)
    end)

    :ok
  end
end
