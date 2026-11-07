defmodule Hueworks.Scenes.LightStates do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.AppSettings
  alias Hueworks.Circadian
  alias Hueworks.Circadian.Config, as: CircadianConfig
  alias Hueworks.Repo
  alias Hueworks.Schemas.{LightState, Area, Scene, SceneComponent}

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

  def editor_label(%{type: :circadian, name: name}), do: "#{name} (circadian)"

  def editor_label(%{type: :manual, name: name, config: config}) do
    suffix =
      case LightState.manual_mode(config) do
        :color -> "manual color"
        _ -> "manual temp"
      end

    "#{name} (#{suffix})"
  end

  def editor_label(%{name: name}), do: name

  def create(name, type, config \\ %{})

  def create(name, type, config) when type in [:manual, :circadian] do
    write_transaction(fn ->
      %LightState{}
      |> LightState.changeset(%{
        name: name,
        type: type,
        config: initial_config(type, config || %{})
      })
      |> validate_event_order(nil)
      |> Repo.insert()
    end)
  end

  def create(_name, _type, _config), do: {:error, :invalid_type}

  def update(id, attrs) when is_integer(id) and is_map(attrs) do
    write_transaction(fn ->
      case Repo.get(LightState, id) do
        nil ->
          {:error, :not_found}

        %LightState{type: type} = state when type in [:manual, :circadian] ->
          config =
            state
            |> LightState.persisted_config()
            |> Map.merge(Map.get(attrs, :config) || Map.get(attrs, "config") || %{})

          merged_attrs =
            Map.merge(%{name: state.name, type: state.type, config: config}, attrs)

          state
          |> LightState.changeset(merged_attrs)
          |> validate_event_order(state)
          |> Repo.update()

        _ ->
          {:error, :invalid_type}
      end
    end)
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
          config: LightState.persisted_config(state)
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

  defp initial_config(:circadian, config) do
    Map.merge(CircadianConfig.new_profile_config(), LightState.persisted_config(config))
  end

  defp initial_config(_type, config), do: config

  # Immediate so a concurrent global timing edit validates against this write.
  defp write_transaction(write) do
    Repo.transaction(
      fn ->
        case write.() do
          {:ok, state} -> state
          {:error, reason} -> Repo.rollback(reason)
        end
      end,
      mode: :immediate
    )
  end

  defp validate_event_order(%Ecto.Changeset{valid?: false} = changeset, _previous), do: changeset

  defp validate_event_order(changeset, previous) do
    state = Ecto.Changeset.apply_changes(changeset)

    if state.type == :circadian and introduces_event_order_conflict?(state, previous) do
      Ecto.Changeset.add_error(
        changeset,
        :config,
        "would put sunrise and sunset out of order for: #{state.name}"
      )
    else
      changeset
    end
  end

  defp introduces_event_order_conflict?(state, previous) do
    solar_config = AppSettings.solar_config()

    case Circadian.local_today(solar_config) do
      {:ok, date} ->
        Circadian.invalid_event_order?(LightState.circadian_config(state), solar_config, date) and
          not previously_invalid?(previous, solar_config, date)

      {:error, _reason} ->
        false
    end
  end

  defp previously_invalid?(nil, _solar_config, _date), do: false

  defp previously_invalid?(%LightState{} = previous, solar_config, date) do
    previous.type == :circadian and
      Circadian.invalid_event_order?(LightState.circadian_config(previous), solar_config, date)
  end

  defp usage_map([]), do: %{}

  defp usage_map(light_state_ids) do
    Repo.all(
      from(sc in SceneComponent,
        join: s in Scene,
        on: s.id == sc.scene_id,
        join: r in Area,
        on: r.id == s.area_id,
        where: sc.light_state_id in ^light_state_ids,
        order_by: [asc: s.name, asc: s.id],
        select: {
          sc.light_state_id,
          %{
            scene_id: s.id,
            scene_name: s.name,
            area_id: r.id,
            area_name: r.name
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
