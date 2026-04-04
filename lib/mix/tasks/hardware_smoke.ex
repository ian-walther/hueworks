defmodule Mix.Tasks.HardwareSmoke do
  use Mix.Task
  require Logger

  @shortdoc "Run explicit hardware smoke scenarios against the dev environment"

  @moduledoc """
  Run manual hardware smoke scenarios against the current dev database and connected bridges.

  These scenarios are intentionally not part of the normal automated test suite.

  Usage:

      ALLOW_HARDWARE_SMOKE=1 mix hardware_smoke kitchen_accent_pico
      ALLOW_HARDWARE_SMOKE=1 mix hardware_smoke kitchen_accent_lower_repeat
      ALLOW_HARDWARE_SMOKE=1 mix hardware_smoke kitchen_accent_pico --loops 10
      ALLOW_HARDWARE_SMOKE=1 mix hardware_smoke kitchen_accent_pico --dry-run
      ALLOW_HARDWARE_SMOKE=1 mix hardware_smoke kitchen_accent_pico --settle-ms 1000
      ALLOW_HARDWARE_SMOKE=1 mix hardware_smoke kitchen_accent_pico --log-level debug
  """

  alias Hueworks.HardwareSmoke

  @impl true
  def run(args) do
    ensure_allowed!()

    {opts, positional, invalid} =
      OptionParser.parse(args,
        strict: [
          loops: :integer,
          timeout_ms: :integer,
          poll_ms: :integer,
          settle_ms: :integer,
          dry_run: :boolean,
          log_level: :string
        ]
      )

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    configure_task_logging!(opts)
    Mix.Task.run("app.start")

    scenario_name = List.first(positional) || Mix.raise("missing scenario name")

    HardwareSmoke.run!(scenario_name, opts)
  end

  defp ensure_allowed! do
    case System.get_env("ALLOW_HARDWARE_SMOKE") do
      "1" -> :ok
      _ -> Mix.raise("set ALLOW_HARDWARE_SMOKE=1 to run hardware smoke scenarios")
    end
  end

  defp configure_task_logging!(opts) do
    level =
      opts
      |> Keyword.get(:log_level, System.get_env("HARDWARE_SMOKE_LOG_LEVEL", "info"))
      |> parse_log_level!()

    Logger.configure(level: level)
    Logger.configure_backend(:console, level: level)
  end

  defp parse_log_level!(value) when is_binary(value) do
    case String.downcase(value) do
      "debug" -> :debug
      "info" -> :info
      "warning" -> :warning
      "error" -> :error
      other ->
        Mix.raise(
          "invalid --log-level #{inspect(other)}; expected debug, info, warning, or error"
        )
    end
  end
end
