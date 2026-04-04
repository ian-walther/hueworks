defmodule Hueworks.Control.Group do
  @moduledoc """
  Dispatcher for group control commands.
  """

  alias Hueworks.Control.{HomeAssistantPayload, HuePayload, Z2MPayload}

  alias Hueworks.Control.{
    HomeAssistantBridge,
    HomeAssistantClient,
    HueBridge,
    HueClient,
    Z2MBridge,
    Z2MClient
  }

  def on(group, opts \\ %{}), do: dispatch(group, :on, normalize_apply_opts(opts))
  def off(group, opts \\ %{}), do: dispatch(group, :off, normalize_apply_opts(opts))

  def set_state(group, desired, opts \\ %{}) when is_map(desired) do
    dispatch(group, {:set_state, desired}, normalize_apply_opts(opts))
  end

  def set_brightness(group, level, opts \\ %{}),
    do: dispatch(group, {:brightness, level}, normalize_apply_opts(opts))

  def set_color_temp(group, kelvin, opts \\ %{}),
    do: dispatch(group, {:color_temp, kelvin}, normalize_apply_opts(opts))

  def set_color(group, hs, opts \\ %{}),
    do: dispatch(group, {:color, hs}, normalize_apply_opts(opts))

  defp dispatch(%{source: :hue} = group, action, apply_opts) do
    with {:ok, host, api_key} <- HueBridge.credentials_for(group),
         payload <- HuePayload.action_payload(action, apply_opts),
         {:ok, _resp} <-
           HueClient.request(host, api_key, "/groups/#{group.source_id}/action", payload) do
      :ok
    else
      {:error, _} = error -> error
    end
  end

  defp dispatch(%{source: :caseta}, _action, _apply_opts) do
    {:error, :not_implemented}
  end

  defp dispatch(%{source: :ha} = group, action, apply_opts) do
    with {:ok, host, token} <- HomeAssistantBridge.credentials_for(group),
         {service, payload} <- HomeAssistantPayload.action_payload(action, group, apply_opts),
         {:ok, _resp} <- HomeAssistantClient.request(host, token, service, payload) do
      :ok
    else
      {:error, _} = error -> error
      :ignore -> :ok
    end
  end

  defp dispatch(%{source: :z2m} = group, action, apply_opts) do
    with {:ok, config} <- Z2MBridge.connection_for(group),
         payload <- Z2MPayload.action_payload(action, group, apply_opts),
         :ok <- Z2MClient.request(config, group, payload) do
      :ok
    else
      {:error, _} = error -> error
      :ignore -> :ok
    end
  end

  defp dispatch(_group, _action, _apply_opts), do: {:error, :unsupported}

  defp normalize_apply_opts(opts) when is_map(opts), do: opts
  defp normalize_apply_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_apply_opts(_opts), do: %{}
end
