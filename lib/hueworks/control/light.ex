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

  def on(light, opts \\ %{}), do: dispatch(light, :on, normalize_apply_opts(opts))
  def off(light, opts \\ %{}), do: dispatch(light, :off, normalize_apply_opts(opts))

  def set_state(light, desired, opts \\ %{}) when is_map(desired) do
    dispatch(light, {:set_state, desired}, normalize_apply_opts(opts))
  end

  def set_brightness(light, level, opts \\ %{}),
    do: dispatch(light, {:brightness, level}, normalize_apply_opts(opts))

  def set_color_temp(light, kelvin, opts \\ %{}),
    do: dispatch(light, {:color_temp, kelvin}, normalize_apply_opts(opts))

  def set_color(light, hs, opts \\ %{}),
    do: dispatch(light, {:color, hs}, normalize_apply_opts(opts))

  defp dispatch(%{source: :hue} = light, action, apply_opts) do
    with {:ok, host, api_key} <- HueBridge.credentials_for(light),
         payload <- HuePayload.action_payload(action, apply_opts),
         {:ok, _resp} <-
           HueClient.request(host, api_key, "/lights/#{light.source_id}/state", payload) do
      :ok
    else
      {:error, _} = error -> error
    end
  end

  defp dispatch(%{source: :caseta} = light, action, _apply_opts) do
    with {:ok, host, ssl_opts} <- CasetaBridge.connection_for(light),
         payload <- CasetaPayload.action_payload(action, light),
         :ok <- CasetaClient.request(host, ssl_opts, payload) do
      :ok
    else
      {:error, _} = error -> error
      :ignore -> :ok
    end
  end

  defp dispatch(%{source: :ha} = light, action, apply_opts) do
    with {:ok, host, token} <- HomeAssistantBridge.credentials_for(light),
         {service, payload} <- HomeAssistantPayload.action_payload(action, light, apply_opts),
         {:ok, _resp} <- HomeAssistantClient.request(host, token, service, payload) do
      :ok
    else
      {:error, _} = error -> error
      :ignore -> :ok
    end
  end

  defp dispatch(%{source: :z2m} = light, action, apply_opts) do
    with {:ok, config} <- Z2MBridge.connection_for(light),
         payload <- Z2MPayload.action_payload(action, light, apply_opts),
         :ok <- Z2MClient.request(config, light, payload) do
      :ok
    else
      {:error, _} = error -> error
      :ignore -> :ok
    end
  end

  defp dispatch(_light, _action, _apply_opts), do: {:error, :unsupported}

  defp normalize_apply_opts(opts) when is_map(opts), do: opts
  defp normalize_apply_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_apply_opts(_opts), do: %{}
end
