defmodule Hueworks.Bridges do
  @moduledoc """
  Bridge lifecycle helpers.
  """

  import Ecto.Query, only: [from: 2, limit: 2]

  alias Hueworks.HomeAssistant.Export, as: HomeAssistantExport
  alias Hueworks.Repo

  alias Hueworks.Schemas.{
    Bridge,
    BridgeImport,
    Group,
    GroupLight,
    Light,
    PicoDevice,
    SceneComponentLight
  }

  def list_bridges do
    Repo.all(Bridge)
  end

  def imported?(%Bridge{} = bridge) do
    bridge.import_complete or bridge_has_entities?(bridge.id)
  end

  def latest_import(%Bridge{id: bridge_id}), do: latest_import(bridge_id)

  def latest_import(bridge_id) when is_integer(bridge_id) do
    BridgeImport
    |> for_bridge(bridge_id)
    |> order_by_latest()
    |> limit(1)
    |> Repo.one()
  end

  def list_imports_for_bridge(bridge_or_id, opts \\ [])

  def list_imports_for_bridge(%Bridge{id: bridge_id}, opts),
    do: list_imports_for_bridge(bridge_id, opts)

  def list_imports_for_bridge(bridge_id, opts) when is_integer(bridge_id) and is_list(opts) do
    bridge_id
    |> imports_query(opts)
    |> Repo.all()
  end

  def prune_imports_for_bridge(%Bridge{id: bridge_id}), do: prune_imports_for_bridge(bridge_id)

  def prune_imports_for_bridge(bridge_id, keep_count \\ 5)
      when is_integer(bridge_id) and is_integer(keep_count) and keep_count > 0 do
    keep_ids =
      bridge_id
      |> imports_query(limit: keep_count)
      |> select_import_id()
      |> Repo.all()

    Repo.delete_all(
      from(bi in BridgeImport,
        where: bi.bridge_id == ^bridge_id and bi.id not in ^keep_ids
      )
    )
  end

  def delete_entities(%Bridge{} = bridge) do
    light_ids =
      Repo.all(from(l in Light, where: l.bridge_id == ^bridge.id, select: l.id))

    group_ids =
      Repo.all(from(g in Group, where: g.bridge_id == ^bridge.id, select: g.id))

    result =
      Repo.transaction(fn ->
        if light_ids != [] do
          Repo.delete_all(from(scl in SceneComponentLight, where: scl.light_id in ^light_ids))
          Repo.delete_all(from(gl in GroupLight, where: gl.light_id in ^light_ids))
        end

        if group_ids != [] do
          Repo.delete_all(from(gl in GroupLight, where: gl.group_id in ^group_ids))
        end

        Repo.delete_all(from(g in Group, where: g.bridge_id == ^bridge.id))
        Repo.delete_all(from(l in Light, where: l.bridge_id == ^bridge.id))
        Repo.delete_all(from(pd in PicoDevice, where: pd.bridge_id == ^bridge.id))

        Repo.update_all(
          from(b in Bridge, where: b.id == ^bridge.id),
          set: [import_complete: false]
        )

        :ok
      end)

    case result do
      {:ok, :ok} ->
        Enum.each(light_ids, &HomeAssistantExport.remove_light/1)
        Enum.each(group_ids, &HomeAssistantExport.remove_group/1)
        result

      _ ->
        result
    end
  end

  def delete_unchecked_entities(%Bridge{} = bridge, light_external_ids, group_external_ids) do
    light_ids =
      light_external_ids
      |> normalize_ids()
      |> fetch_light_ids(bridge.id)

    group_ids =
      group_external_ids
      |> normalize_ids()
      |> fetch_group_ids(bridge.id)

    result =
      Repo.transaction(fn ->
        if light_ids != [] do
          Repo.delete_all(from(scl in SceneComponentLight, where: scl.light_id in ^light_ids))
          Repo.delete_all(from(gl in GroupLight, where: gl.light_id in ^light_ids))
        end

        if group_ids != [] do
          Repo.delete_all(from(gl in GroupLight, where: gl.group_id in ^group_ids))
        end

        if group_ids != [] do
          Repo.delete_all(from(g in Group, where: g.id in ^group_ids))
        end

        if light_ids != [] do
          Repo.delete_all(from(l in Light, where: l.id in ^light_ids))
        end

        if bridge.type == :caseta do
          Repo.delete_all(from(pd in PicoDevice, where: pd.bridge_id == ^bridge.id))
        end

        :ok
      end)

    case result do
      {:ok, :ok} ->
        Enum.each(light_ids, &HomeAssistantExport.remove_light/1)
        Enum.each(group_ids, &HomeAssistantExport.remove_group/1)
        result

      _ ->
        result
    end
  end

  def delete_bridge(%Bridge{} = bridge) do
    Repo.delete(bridge)
  end

  defp imports_query(bridge_id, opts) do
    status = Keyword.get(opts, :status)
    limit_value = Keyword.get(opts, :limit)

    BridgeImport
    |> for_bridge(bridge_id)
    |> maybe_filter_status(status)
    |> order_by_latest()
    |> maybe_limit(limit_value)
  end

  defp for_bridge(query, bridge_id) do
    from(bi in query, where: bi.bridge_id == ^bridge_id)
  end

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, status) do
    from(bi in query, where: bi.status == ^status)
  end

  defp order_by_latest(query) do
    from(bi in query, order_by: [desc: bi.imported_at, desc: bi.id])
  end

  defp maybe_limit(query, nil), do: query

  defp maybe_limit(query, limit_value) when is_integer(limit_value),
    do: from(bi in query, limit: ^limit_value)

  defp select_import_id(query) do
    from(bi in query, select: bi.id)
  end

  defp normalize_ids(ids) do
    ids
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp fetch_light_ids([], _bridge_id), do: []

  defp fetch_light_ids(external_ids, bridge_id) do
    Repo.all(
      from(l in Light,
        where: l.bridge_id == ^bridge_id and l.external_id in ^external_ids,
        select: l.id
      )
    )
  end

  defp fetch_group_ids([], _bridge_id), do: []

  defp fetch_group_ids(external_ids, bridge_id) do
    Repo.all(
      from(g in Group,
        where: g.bridge_id == ^bridge_id and g.external_id in ^external_ids,
        select: g.id
      )
    )
  end

  defp bridge_has_entities?(bridge_id) do
    Repo.exists?(from(l in Light, where: l.bridge_id == ^bridge_id)) or
      Repo.exists?(from(g in Group, where: g.bridge_id == ^bridge_id))
  end
end
