defmodule Hueworks.Control.Light do
  @moduledoc """
  Dispatcher for light control commands.
  """

  alias Hueworks.Control.{
    CasetaPayload,
    DispatchReceipt,
    HomeAssistantPayload,
    HuePayload,
    Z2MPayload
  }

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

  def set_state(light, desired, opts \\ %{}) when is_map(desired) do
    light
    |> dispatch_state(desired, opts)
    |> legacy_result()
  end

  def dispatch_state(light, desired, opts \\ %{}) when is_map(desired) do
    dispatch(light, {:set_state, desired}, normalize_apply_opts(opts))
  end

  defp dispatch(%{source: :hue} = light, action, apply_opts) do
    with {:ok, host, api_key} <- HueBridge.credentials_for(light),
         payload <- HuePayload.action_payload(action, apply_opts),
         {:ok, _resp} <-
           HueClient.request(host, api_key, "/lights/#{light.source_id}/state", payload) do
      {:ok, DispatchReceipt.new(HuePayload.effective_transition_ms(apply_opts))}
    else
      {:error, _} = error -> error
    end
  end

  defp dispatch(%{source: :caseta} = light, action, _apply_opts) do
    with {:ok, host, ssl_opts} <- CasetaBridge.connection_for(light),
         payload <- CasetaPayload.action_payload(action, light),
         :ok <- CasetaClient.request(host, ssl_opts, payload) do
      {:ok, DispatchReceipt.new(0)}
    else
      {:error, _} = error -> error
      :ignore -> :ok
    end
  end

  defp dispatch(%{source: :ha} = light, action, apply_opts) do
    with {:ok, host, token} <- HomeAssistantBridge.credentials_for(light),
         {service, payload} <- HomeAssistantPayload.action_payload(action, light, apply_opts),
         {:ok, _resp} <- HomeAssistantClient.request(host, token, service, payload) do
      {:ok, DispatchReceipt.new(HomeAssistantPayload.effective_transition_ms(apply_opts))}
    else
      {:error, _} = error -> error
      :ignore -> :ok
    end
  end

  defp dispatch(%{source: :z2m} = light, action, apply_opts) do
    with {:ok, config} <- Z2MBridge.connection_for(light),
         payload <- Z2MPayload.action_payload(action, light, apply_opts),
         :ok <- Z2MClient.request(config, light, payload) do
      {:ok, DispatchReceipt.new(Z2MPayload.effective_transition_ms(apply_opts))}
    else
      {:error, _} = error -> error
      :ignore -> :ok
    end
  end

  defp dispatch(_light, _action, _apply_opts), do: {:error, :unsupported}

  defp legacy_result({:ok, _receipt}), do: :ok
  defp legacy_result(other), do: other

  defp normalize_apply_opts(opts) when is_map(opts), do: opts
  defp normalize_apply_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_apply_opts(_opts), do: %{}
end
