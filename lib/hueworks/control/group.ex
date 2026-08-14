defmodule Hueworks.Control.Group do
  @moduledoc """
  Dispatcher for group control commands.
  """

  alias Hueworks.Control.{DispatchReceipt, HomeAssistantPayload, HuePayload, Z2MPayload}

  alias Hueworks.Control.{
    HomeAssistantBridge,
    HomeAssistantClient,
    HueBridge,
    HueClient,
    Z2MBridge,
    Z2MClient
  }

  def dispatch_state(group, desired, opts \\ %{}) when is_map(desired) do
    dispatch(group, {:set_state, desired}, normalize_apply_opts(opts))
  end

  defp dispatch(%{source: :hue} = group, action, apply_opts) do
    with {:ok, host, api_key} <- HueBridge.credentials_for(group),
         payload when is_map(payload) <- HuePayload.action_payload(action, apply_opts),
         {:ok, _resp} <-
           HueClient.request(host, api_key, "/groups/#{group.source_id}/action", payload) do
      {:ok, DispatchReceipt.new(HuePayload.effective_transition_ms(apply_opts))}
    else
      {:error, _} = error -> error
      :ignore -> :ok
    end
  end

  defp dispatch(%{source: :ha} = group, action, apply_opts) do
    with {service, payload} <- HomeAssistantPayload.action_payload(action, group, apply_opts),
         {:ok, _resp} <-
           HomeAssistantBridge.request(group, fn host, token ->
             HomeAssistantClient.request(host, token, service, payload)
           end) do
      {:ok, DispatchReceipt.new(HomeAssistantPayload.effective_transition_ms(apply_opts))}
    else
      {:error, _} = error -> error
      :ignore -> :ok
    end
  end

  defp dispatch(%{source: :z2m} = group, action, apply_opts) do
    with {:ok, config} <- Z2MBridge.connection_for(group),
         payload when is_map(payload) <- Z2MPayload.action_payload(action, group, apply_opts),
         :ok <- Z2MClient.request(config, group, payload) do
      {:ok, DispatchReceipt.new(Z2MPayload.effective_transition_ms(apply_opts))}
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
