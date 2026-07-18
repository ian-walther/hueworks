defmodule Hueworks.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    opts = [strategy: :one_for_one, name: Hueworks.Supervisor]
    Supervisor.start_link(children(), opts)
  end

  def children(runtime_io_disabled \\ Hueworks.RuntimeIO.disabled?()) do
    safe_children = [
      Hueworks.Repo,
      {Phoenix.PubSub, name: Hueworks.PubSub},
      HueworksApp.Cache.Store,
      Hueworks.Control.State,
      Hueworks.Control.DesiredState,
      Hueworks.Control.TraceBuffer
    ]

    runtime_children =
      if runtime_io_disabled do
        []
      else
        [
          Hueworks.Control.Executor,
          maybe_circadian_poller(),
          Hueworks.Subscription.HueEventStream,
          Hueworks.Subscription.HomeAssistantEventStream,
          Hueworks.Subscription.CasetaEventStream,
          Hueworks.Subscription.Z2MEventStream,
          maybe_home_assistant_export(),
          maybe_homekit_bridge()
        ]
        |> Enum.reject(&is_nil/1)
      end

    safe_children ++ runtime_children ++ [HueworksWeb.Endpoint]
  end

  @impl true
  def config_change(changed, _new, removed) do
    HueworksWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp maybe_circadian_poller do
    if Application.get_env(:hueworks, :circadian_poll_enabled, true) do
      Hueworks.Control.CircadianPoller
    else
      nil
    end
  end

  defp maybe_home_assistant_export do
    if Application.get_env(:hueworks, :ha_export_runtime_enabled, true) do
      Hueworks.HomeAssistant.Export
    else
      nil
    end
  end

  defp maybe_homekit_bridge do
    if Application.get_env(:hueworks, :homekit_runtime_enabled, true) do
      Hueworks.HomeKit.Bridge
    else
      nil
    end
  end
end
