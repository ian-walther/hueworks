defmodule Hueworks.Health do
  @moduledoc false

  alias Hueworks.Control.{DesiredState, Executor, State}
  alias Hueworks.Repo
  alias Hueworks.RuntimeIO

  def status do
    database = database_status()
    runtime_io_disabled? = RuntimeIO.disabled?()

    runtime = %{
      control_state: process_status(State),
      desired_state: process_status(DesiredState),
      executor: if(runtime_io_disabled?, do: "disabled", else: process_status(Executor))
    }

    required_runtime =
      if runtime_io_disabled? do
        Map.take(runtime, [:control_state, :desired_state])
      else
        runtime
      end

    ready? =
      database == "ok" and Enum.all?(required_runtime, fn {_name, status} -> status == "ok" end)

    body = %{
      status: if(ready?, do: "ok", else: "unavailable"),
      version: version(),
      database: database,
      runtime: runtime
    }

    body = if runtime_io_disabled?, do: Map.put(body, :runtime_io, "disabled"), else: body

    %{
      ready?: ready?,
      body: body
    }
  end

  def version do
    case Application.spec(:hueworks, :vsn) do
      nil -> "unknown"
      version -> to_string(version)
    end
  end

  defp database_status do
    case Repo.query("SELECT 1", []) do
      {:ok, _result} -> "ok"
      _other -> "error"
    end
  rescue
    _error -> "error"
  catch
    :exit, _reason -> "error"
  end

  defp process_status(name) do
    case Process.whereis(name) do
      pid when is_pid(pid) -> "ok"
      nil -> "error"
    end
  end
end
