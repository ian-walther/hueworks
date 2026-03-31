defmodule Hueworks.Control.State do
  @moduledoc """
  Shared in-memory control state backed by ETS.
  """

  use GenServer
  import Ecto.Query, only: [from: 2]

  alias Ecto.Adapters.SQL.Sandbox
  alias Hueworks.Control.Bootstrap.HomeAssistant
  alias Hueworks.Control.Bootstrap.Hue
  alias Hueworks.Control.LightStateSemantics
  alias Hueworks.Control.Bootstrap.Z2M
  alias Hueworks.Control.DesiredState
  alias Hueworks.ActiveScenes
  alias Hueworks.DebugLogging
  alias Hueworks.Repo
  alias Hueworks.Schemas.Light
  alias HueworksApp.Cache
  alias Phoenix.PubSub

  @table :hueworks_control_state
  @topic "control_state"
  @light_room_cache_namespace :light_room_ids
  @light_compare_cache_namespace :light_compare_entities
  @default_light_room_cache_ttl_ms 60_000
  @default_bootstrap_scene_clear_suppress_ms 10_000
  @brightness_tolerance 2
  @temperature_scene_clear_mired_tolerance 1

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    if :ets.whereis(@table) != :undefined do
      :ets.delete(@table)
    end

    :ets.new(@table, [:named_table, :public, read_concurrency: true, write_concurrency: true])
    {:ok, %{}, {:continue, :bootstrap}}
  end

  def get(type, id) do
    case :ets.lookup(@table, {type, id}) do
      [{_key, state}] -> state
      [] -> nil
    end
  end

  def ensure(type, id, defaults) when is_map(defaults) do
    GenServer.call(__MODULE__, {:ensure, type, id, defaults})
  end

  def put(type, id, attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    GenServer.call(__MODULE__, {:put, type, id, attrs, self(), opts})
  end

  def bootstrap do
    GenServer.cast(__MODULE__, :bootstrap)
  end

  def suppress_scene_clear_for_refresh do
    GenServer.call(__MODULE__, :suppress_scene_clear)
  end

  def clear_scene_clear_suppression do
    GenServer.call(__MODULE__, :clear_scene_clear_suppression)
  end

  @impl true
  def handle_continue(:bootstrap, state) do
    do_bootstrap()
    {:noreply, state}
  end

  @impl true
  def handle_call({:ensure, type, id, defaults}, _from, state) do
    key = {type, id}

    case :ets.lookup(@table, key) do
      [{_key, current}] ->
        {:reply, current, state}

      [] ->
        :ets.insert(@table, {key, defaults})
        {:reply, defaults, state}
    end
  end

  @impl true
  def handle_call({:put, type, id, attrs, caller, opts}, _from, state) do
    key = {type, id}

    allow_repo_access(caller)
    updated = merge_and_store(key, attrs, caller, opts, state)
    {:reply, updated, state}
  end

  @impl true
  def handle_call(:suppress_scene_clear, _from, state) do
    {:reply, :ok, suppress_scene_clear(state)}
  end

  @impl true
  def handle_call(:clear_scene_clear_suppression, _from, state) do
    {:reply, :ok, Map.delete(state, :scene_clear_suppressed_until_ms)}
  end

  @impl true
  def handle_cast(:bootstrap, state) do
    do_bootstrap()
    {:noreply, state}
  end

  defp do_bootstrap do
    Task.start(fn ->
      Hue.run()
      HomeAssistant.run()
      Z2M.run()
    end)
  end

  defp merge_and_store(key, attrs, caller, opts, state) do
    current =
      case :ets.lookup(@table, key) do
        [{_key, existing}] -> existing
        [] -> %{}
      end

    updated = Map.merge(current, attrs)
    maybe_deactivate_scene_on_external_change(key, updated, caller, opts, state)
    :ets.insert(@table, {key, updated})
    broadcast_update(key, updated)
    updated
  end

  defp broadcast_update({type, id}, state) do
    PubSub.broadcast(Hueworks.PubSub, @topic, {:control_state, type, id, state})
  end

  defp maybe_deactivate_scene_on_external_change({:light, light_id}, updated, caller, opts, state) do
    if Keyword.get(opts, :source) == :bootstrap or scene_clear_suppressed?(state) do
      :ok
    else
      desired = DesiredState.get(:light, light_id) || %{}
      diverging_keys = diverging_keys(desired, updated)

      cond do
        desired == %{} ->
          :ok

        diverging_keys == [] ->
          :ok

        power_only_divergence?(diverging_keys) ->
          :ok

        true ->
          effective_desired = effective_desired_for_light(light_id, desired, caller)

          if effective_desired == %{} or
               diverged_from_desired?(effective_desired, updated) == false do
            :ok
          else
            case light_room_id(light_id, caller) do
              room_id when is_integer(room_id) ->
                case ActiveScenes.get_for_room(room_id) do
                  nil ->
                    :ok

                  active_scene ->
                    pending? = active_scene_pending?(active_scene)

                    DebugLogging.info(
                      "[scene-clear-trace] light_id=#{light_id} room_id=#{room_id} " <>
                        "active_scene_id=#{inspect(active_scene_id(active_scene))} " <>
                        "pending=#{pending?} desired=#{inspect(desired)} " <>
                        "effective_desired=#{inspect(effective_desired)} updated=#{inspect(updated)}"
                    )

                    if pending? do
                      :ok
                    else
                      _ = ActiveScenes.clear_for_room(room_id)
                    end

                    :ok
                end

              _ ->
                :ok
            end
          end
      end
    end
  end

  defp maybe_deactivate_scene_on_external_change(_key, _updated, _caller, _opts, _state), do: :ok

  defp suppress_scene_clear(state) do
    Map.put(
      state,
      :scene_clear_suppressed_until_ms,
      System.monotonic_time(:millisecond) + bootstrap_scene_clear_suppress_ms()
    )
  end

  defp scene_clear_suppressed?(state) do
    case Map.get(state, :scene_clear_suppressed_until_ms) do
      until_ms when is_integer(until_ms) ->
        System.monotonic_time(:millisecond) < until_ms

      _ ->
        false
    end
  end

  defp active_scene_pending?(%{pending_until: %DateTime{} = pending_until}) do
    DateTime.compare(pending_until, DateTime.utc_now()) == :gt
  end

  defp active_scene_pending?(_active_scene), do: false

  defp active_scene_id(%{scene_id: scene_id}) when is_integer(scene_id), do: scene_id
  defp active_scene_id(_active_scene), do: nil

  defp light_room_id(light_id, caller) when is_integer(light_id) do
    Cache.get_or_load(
      @light_room_cache_namespace,
      light_id,
      fn ->
        Repo.one(from(l in Light, where: l.id == ^light_id, select: l.room_id), caller: caller)
      end,
      ttl_ms: light_room_cache_ttl_ms()
    )
  end

  defp light_room_id(_light_id, _caller), do: nil

  defp effective_desired_for_light(light_id, desired, caller)
       when is_integer(light_id) and is_map(desired) do
    case light_for_desired_comparison(light_id, caller) do
      %Light{} = light ->
        LightStateSemantics.effective_desired_for_light(desired, light)

      _ ->
        desired
    end
  end

  defp effective_desired_for_light(_light_id, desired, _caller), do: desired

  defp light_for_desired_comparison(light_id, caller) when is_integer(light_id) do
    Cache.get_or_load(
      @light_compare_cache_namespace,
      light_id,
      fn -> Repo.get(Light, light_id, caller: caller) end,
      ttl_ms: light_room_cache_ttl_ms()
    )
  end

  defp light_for_desired_comparison(_light_id, _caller), do: nil

  defp light_room_cache_ttl_ms do
    Application.get_env(
      :hueworks,
      :cache_light_room_ttl_ms,
      @default_light_room_cache_ttl_ms
    )
  end

  defp bootstrap_scene_clear_suppress_ms do
    Application.get_env(
      :hueworks,
      :bootstrap_scene_clear_suppress_ms,
      @default_bootstrap_scene_clear_suppress_ms
    )
  end

  defp allow_repo_access(caller) when is_pid(caller) do
    if Repo.config()[:pool] == Sandbox do
      case Sandbox.allow(Repo, caller, self()) do
        :ok -> :ok
        {:already, _} -> :ok
        {:error, _} -> :ok
        :not_found -> :ok
      end
    else
      :ok
    end
  end

  defp allow_repo_access(_caller), do: :ok

  defp diverged_from_desired?(desired, updated) do
    LightStateSemantics.diverging_keys(desired, updated,
      brightness_tolerance: @brightness_tolerance,
      temperature_mired_tolerance: @temperature_scene_clear_mired_tolerance
    ) != []
  end

  defp diverging_keys(desired, updated) do
    LightStateSemantics.diverging_keys(desired, updated,
      brightness_tolerance: @brightness_tolerance,
      temperature_mired_tolerance: @temperature_scene_clear_mired_tolerance
    )
  end

  defp power_only_divergence?(keys) do
    keys
    |> Enum.map(fn
      :power -> :power
      "power" -> :power
      key -> key
    end)
    |> Enum.uniq()
    |> case do
      [:power] -> true
      _ -> false
    end
  end
end
