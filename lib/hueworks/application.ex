defmodule Hueworks.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Hueworks.Repo,
      {Phoenix.PubSub, name: Hueworks.PubSub},
      Hueworks.Control.State,
      Hueworks.Subscription.HueEventStream,
      Hueworks.Subscription.HomeAssistantEventStream,
      Hueworks.Subscription.CasetaEventStream,
      HueworksWeb.FilterPrefs,
      HueworksWeb.Endpoint
      # Exploration modules will be started manually in iex for now
      # {Hueworks.Exploration.PicoHueSlice, []},
    ]

    opts = [strategy: :one_for_one, name: Hueworks.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    HueworksWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
