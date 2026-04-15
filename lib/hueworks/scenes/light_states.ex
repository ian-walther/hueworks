defmodule Hueworks.Scenes.LightStates do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Repo
  alias Hueworks.Schemas.{LightState, Room, Scene, SceneComponent}

  def list_manual do
    Repo.all(
      from(ls in LightState,
        where: ls.type == :manual,
        order_by: [asc: ls.name, asc: ls.id]
      )
    )
  end

  def list_editable do
    Repo.all(
      from(ls in LightState,
        where: ls.type in [:manual, :circadian],
        order_by: [asc: ls.name, asc: ls.id]
      )
    )
  end

  def list_editable_with_usage do
    states = list_editable()
    usage_by_state_id = usage_map(Enum.map(states, & &1.id))

    Enum.map(states, fn state ->
      usages = Map.get(usage_by_state_id, state.id, [])

      %{
        state: state,
        usage_count: length(usages),
        usages: usages
      }
    end)
  end

  def get_editable(id) when is_integer(id) do
    case Repo.get(LightState, id) do
      %LightState{type: type} = state when type in [:manual, :circadian] -> state
      _ -> nil
    end
  end

  def get_editable(_id), do: nil

  def usages(id) when is_integer(id) do
    Map.get(usage_map([id]), id, [])
  end

  def usages(_id), do: []

  def create(name, type, config \\ %{})

  def create(name, type, config) when type in [:manual, :circadian] do
    %LightState{}
    |> LightState.changeset(%{
      name: name,
      type: type,
      config: config || %{}
    })
    |> Repo.insert()
  end

  def create(_name, _type, _config), do: {:error, :invalid_type}

  def update(id, attrs) when is_integer(id) and is_map(attrs) do
    case Repo.get(LightState, id) do
      nil ->
        {:error, :not_found}

      %LightState{type: type} = state when type in [:manual, :circadian] ->
        config =
          state.config
          |> Kernel.||(%{})
          |> Map.merge(Map.get(attrs, :config) || Map.get(attrs, "config") || %{})

        merged_attrs = Map.merge(%{name: state.name, type: state.type, config: config}, attrs)

        state
        |> LightState.changeset(merged_attrs)
        |> Repo.update()

      _ ->
        {:error, :invalid_type}
    end
  end

  def duplicate(id) when is_integer(id) do
    case Repo.get(LightState, id) do
      nil ->
        {:error, :not_found}

      %LightState{type: type} = state when type in [:manual, :circadian] ->
        %LightState{}
        |> LightState.changeset(%{
          name: "#{state.name} Copy",
          type: state.type,
          config: Map.new(state.config || %{})
        })
        |> Repo.insert()

      _ ->
        {:error, :invalid_type}
    end
  end

  def delete(id) when is_integer(id) do
    case Repo.get(LightState, id) do
      nil ->
        {:error, :not_found}

      %LightState{type: type} = state when type in [:manual, :circadian] ->
        in_use =
          Repo.aggregate(
            from(sc in SceneComponent, where: sc.light_state_id == ^state.id),
            :count
          )

        if in_use == 0 do
          Repo.delete(state)
        else
          {:error, :in_use}
        end

      _ ->
        {:error, :invalid_type}
    end
  end

  def delete(_id), do: {:error, :not_found}

  defp usage_map([]), do: %{}

  defp usage_map(light_state_ids) do
    Repo.all(
      from(sc in SceneComponent,
        join: s in Scene,
        on: s.id == sc.scene_id,
        join: r in Room,
        on: r.id == s.room_id,
        where: sc.light_state_id in ^light_state_ids,
        order_by: [asc: s.name, asc: s.id],
        select: {
          sc.light_state_id,
          %{
            scene_id: s.id,
            scene_name: s.name,
            room_id: r.id,
            room_name: r.name
          }
        }
      )
    )
    |> Enum.uniq_by(fn {light_state_id, usage} -> {light_state_id, usage.scene_id} end)
    |> Enum.group_by(fn {light_state_id, _usage} -> light_state_id end, fn {_light_state_id,
                                                                            usage} ->
      usage
    end)
  end
end
