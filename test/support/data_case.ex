defmodule Hueworks.DataCase do
  use ExUnit.CaseTemplate

  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge

  using do
    quote do
      alias Hueworks.Repo
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Hueworks.DataCase
    end
  end

  setup tags do
    Hueworks.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Hueworks.Repo, shared: not tags[:async])
    :ok = HueworksApp.Cache.flush_all()
    clear_ets(:hueworks_desired_state)
    clear_ets(:hueworks_control_state)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  def insert_bridge!(attrs) when is_map(attrs) do
    %Bridge{}
    |> Bridge.changeset(attrs)
    |> Repo.insert!()
  end

  def restore_app_env(app, key, nil) do
    Application.delete_env(app, key)
  end

  def restore_app_env(app, key, value) do
    Application.put_env(app, key, value)
  end

  defp clear_ets(table) do
    if :ets.whereis(table) != :undefined do
      :ets.delete_all_objects(table)
    end

    :ok
  end
end
