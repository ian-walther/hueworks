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

  def on(group), do: dispatch(group, :on)
  def off(group), do: dispatch(group, :off)
  def set_state(group, desired) when is_map(desired), do: dispatch(group, {:set_state, desired})
  def set_brightness(group, level), do: dispatch(group, {:brightness, level})
  def set_color_temp(group, kelvin), do: dispatch(group, {:color_temp, kelvin})
  def set_color(group, hs), do: dispatch(group, {:color, hs})

  defp dispatch(%{source: :hue} = group, action) do
    with {:ok, host, api_key} <- HueBridge.credentials_for(group),
         payload <- HuePayload.action_payload(action),
         {:ok, _resp} <-
           HueClient.request(host, api_key, "/groups/#{group.source_id}/action", payload) do
      :ok
    else
      {:error, _} = error -> error
    end
  end

  defp dispatch(%{source: :caseta}, _action) do
    {:error, :not_implemented}
  end

  defp dispatch(%{source: :ha} = group, action) do
    with {:ok, host, token} <- HomeAssistantBridge.credentials_for(group),
         {service, payload} <- HomeAssistantPayload.action_payload(action, group),
         {:ok, _resp} <- HomeAssistantClient.request(host, token, service, payload) do
      :ok
    else
      {:error, _} = error -> error
      :ignore -> :ok
    end
  end

  defp dispatch(%{source: :z2m} = group, action) do
    with {:ok, config} <- Z2MBridge.connection_for(group),
         payload <- Z2MPayload.action_payload(action, group),
         :ok <- Z2MClient.request(config, group, payload) do
      :ok
    else
      {:error, _} = error -> error
      :ignore -> :ok
    end
  end

  defp dispatch(_group, _action), do: {:error, :unsupported}
end
