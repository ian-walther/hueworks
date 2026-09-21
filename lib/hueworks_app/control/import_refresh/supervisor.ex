defmodule Hueworks.Control.ImportRefresh.Supervisor do
  @moduledoc false
  use Supervisor

  alias Hueworks.Control.ImportRefresh

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    tasks = Keyword.get(opts, :task_supervisor, ImportRefresh.task_supervisor())

    worker_opts =
      opts
      |> Keyword.put(:name, Keyword.get(opts, :worker_name, ImportRefresh))
      |> Keyword.put(:task_supervisor, tasks)

    # A replacement coordinator must not race orphaned tasks from its predecessor.
    Supervisor.init(
      [
        {Task.Supervisor, name: tasks},
        {ImportRefresh, worker_opts}
      ],
      strategy: :one_for_all
    )
  end
end
