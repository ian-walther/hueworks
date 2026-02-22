defmodule Hueworks.Control.Light do
  @moduledoc """
  Dispatcher for light control commands.
  """

  alias Hueworks.Control.{CasetaPayload, HomeAssistantPayload, HuePayload, Z2MPayload}

  alias Hueworks.Control.{
    CasetaBridge,
    CasetaClient,
    HomeAssistantBridge,
    HomeAssistantClient,
    HueBridge,
    HueClient,
    Z2MBridge,
    Z2MClient
  }

  def on(light), do: dispatch(light, :on)
  def off(light), do: dispatch(light, :off)
  def set_state(light, desired) when is_map(desired), do: dispatch(light, {:set_state, desired})
  def set_brightness(light, level), do: dispatch(light, {:brightness, level})
  def set_color_temp(light, kelvin), do: dispatch(light, {:color_temp, kelvin})
  def set_color(light, hs), do: dispatch(light, {:color, hs})

  defp dispatch(%{source: :hue} = light, action) do
    with {:ok, host, api_key} <- HueBridge.credentials_for(light),
         payload <- HuePayload.action_payload(action),
         {:ok, _resp} <-
           HueClient.request(host, api_key, "/lights/#{light.source_id}/state", payload) do
      :ok
    else
      {:error, _} = error -> error
    end
  end

  defp dispatch(%{source: :caseta} = light, action) do
    with {:ok, host, ssl_opts} <- CasetaBridge.connection_for(light),
         payload <- CasetaPayload.action_payload(action, light),
         :ok <- CasetaClient.request(host, ssl_opts, payload) do
      :ok
    else
      {:error, _} = error -> error
      :ignore -> :ok
    end
  end

  defp dispatch(%{source: :ha} = light, action) do
    with {:ok, host, token} <- HomeAssistantBridge.credentials_for(light),
         {service, payload} <- HomeAssistantPayload.action_payload(action, light),
         {:ok, _resp} <- HomeAssistantClient.request(host, token, service, payload) do
      :ok
    else
      {:error, _} = error -> error
      :ignore -> :ok
    end
  end

  defp dispatch(%{source: :z2m} = light, action) do
    with {:ok, config} <- Z2MBridge.connection_for(light),
         payload <- Z2MPayload.action_payload(action, light),
         :ok <- Z2MClient.request(config, light, payload) do
      :ok
    else
      {:error, _} = error -> error
      :ignore -> :ok
    end
  end

  defp dispatch(_light, _action), do: {:error, :unsupported}
end
