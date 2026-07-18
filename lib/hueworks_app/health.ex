defmodule Hueworks.Health do
  @moduledoc false

  alias Hueworks.Control.{DesiredState, Executor, State}
  alias Hueworks.Repo

  def status do
    database = database_status()

    runtime = %{
      control_state: process_status(State),
      desired_state: process_status(DesiredState),
      executor: process_status(Executor)
    }

    ready? = database == "ok" and Enum.all?(runtime, fn {_name, status} -> status == "ok" end)

    %{
      ready?: ready?,
      body: %{
        status: if(ready?, do: "ok", else: "unavailable"),
        version: version(),
        database: database,
        runtime: runtime
      }
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
