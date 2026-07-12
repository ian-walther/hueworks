defmodule Hueworks.HomeAssistant.Export.Router.SceneCommands do
  @moduledoc false

  require Logger

  alias Hueworks.ActiveScenes
  alias Hueworks.HomeAssistant.Export.Entities
  alias Hueworks.Scenes
  alias Hueworks.Schemas.Scene

  def handle_scene_command(scene_id, payload) when is_integer(scene_id) and is_binary(payload) do
    case scene_activation_opts(payload) do
      {:ok, opts} -> activate_scene(scene_id, opts)
      :error -> log_invalid_command("scene", scene_id, payload)
    end
  end

  def handle_scene_command(_scene_id, _payload), do: :ok

  def activate_scene(scene_id, opts \\ [])

  def activate_scene(scene_id, opts) when is_integer(scene_id) and is_list(opts) do
    trace = %{source: :home_assistant_mqtt_export}

    case Scenes.activate_scene(scene_id, Keyword.put(opts, :trace, trace)) do
      {:ok, _diff, _updated} ->
        :ok

      {:error, reason} ->
        Logger.warning("HA export scene activation failed: #{inspect(reason)}")
    end
  end

  def activate_scene(_scene_id, _opts), do: :ok

  def handle_room_select_command(room_id, payload)
      when is_integer(room_id) and is_binary(payload) do
    case room_select_command(payload) do
      {:clear, _opts} ->
        ActiveScenes.clear_for_room(room_id)

      {:select, option_label, opts} ->
        room_id
        |> Entities.scene_for_room_option(option_label)
        |> case do
          %Scene{} = scene ->
            trace = %{source: :home_assistant_mqtt_export_select}

            case Scenes.activate_scene(scene.id, Keyword.put(opts, :trace, trace)) do
              {:ok, _diff, _updated} ->
                :ok

              {:error, reason} ->
                Logger.warning("HA export room select activation failed: #{inspect(reason)}")
            end

          nil ->
            log_invalid_command("room select", room_id, payload, "unknown option")
        end

      :error ->
        log_invalid_command("room select", room_id, payload)
    end
  end

  def handle_room_select_command(_room_id, _option_label), do: :ok

  defp scene_activation_opts("ON"), do: {:ok, []}

  defp scene_activation_opts(payload) do
    payload
    |> Jason.decode()
    |> case do
      {:ok, %{"transition_ms" => duration_ms}} -> transition_opts(duration_ms)
      _ -> :error
    end
  end

  defp room_select_command(payload) do
    if json_payload?(payload) do
      case Jason.decode(payload) do
        {:ok, %{"option" => option_label, "transition_ms" => duration_ms}}
        when is_binary(option_label) ->
          transition_opts(duration_ms)
          |> case do
            {:ok, opts} -> room_select_option(option_label, opts)
            :error -> :error
          end

        _ ->
          :error
      end
    else
      room_select_option(payload, [])
    end
  end

  defp room_select_option(option_label, opts) when option_label in ["Manual", "None", ""],
    do: {:clear, opts}

  defp room_select_option(option_label, opts), do: {:select, option_label, opts}

  defp transition_opts(duration_ms) when is_integer(duration_ms) and duration_ms > 0,
    do: {:ok, [transition_ms: duration_ms]}

  defp transition_opts(_duration_ms), do: :error

  defp json_payload?(payload) do
    payload
    |> String.trim_leading()
    |> case do
      <<"{", _::binary>> -> true
      <<"[", _::binary>> -> true
      _ -> false
    end
  end

  defp log_invalid_command(kind, id, payload) do
    Logger.warning("HA export #{kind} command ignored id=#{id} payload=#{inspect(payload)}")
    :ok
  end

  defp log_invalid_command(kind, id, payload, reason) do
    Logger.warning(
      "HA export #{kind} command ignored id=#{id} reason=#{reason} payload=#{inspect(payload)}"
    )

    :ok
  end
end
