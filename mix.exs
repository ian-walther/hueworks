defmodule Hueworks.MixProject do
  use Mix.Project

  def project do
    [
      app: :hueworks,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Hueworks.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Database
      {:ecto_sql, "~> 3.11"},
      {:ecto_sqlite3, "~> 0.15"},

      # HTTP clients
      {:httpoison, "~> 2.2"},
      {:jason, "~> 1.4"},

      # MQTT for Zigbee2MQTT
      {:tortoise, "~> 0.10"},

      # Phoenix for web UI
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 0.20"},
      {:phoenix_html, "~> 4.0"},
      {:plug_cowboy, "~> 2.7"},
      {:bandit, "~> 1.0"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},

      # Development
      {:phoenix_live_reload, "~> 1.4", only: :dev}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind hueworks", "esbuild hueworks"],
      "assets.deploy": [
        "tailwind hueworks --minify",
        "esbuild hueworks --minify",
        "phx.digest"
      ]
    ]
  end
end
