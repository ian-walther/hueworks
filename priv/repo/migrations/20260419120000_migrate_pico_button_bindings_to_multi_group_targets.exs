defmodule Hueworks.Repo.Migrations.MigratePicoButtonBindingsToMultiGroupTargets do
  use Ecto.Migration

  alias Ecto.Adapters.SQL

  def up do
    repo = repo()

    repo
    |> SQL.query!(
      """
      SELECT pb.id, pb.action_config, pd.metadata
      FROM pico_buttons AS pb
      JOIN pico_devices AS pd ON pd.id = pb.pico_device_id
      WHERE pb.action_config IS NOT NULL
      """,
      []
    )
    |> Map.fetch!(:rows)
    |> Enum.each(fn [button_id, action_config, metadata] ->
      action_config = decode_json(action_config)
      metadata = decode_json(metadata)

      case migrate_action_config(action_config, metadata) do
        {:ok, migrated_action_config} ->
          SQL.query!(
            repo,
            "UPDATE pico_buttons SET action_config = ? WHERE id = ?",
            [Jason.encode!(migrated_action_config), button_id]
          )

        :clear_binding ->
          SQL.query!(
            repo,
            "UPDATE pico_buttons SET action_type = NULL, action_config = NULL WHERE id = ?",
            [button_id]
          )

        :noop ->
          :ok
      end
    end)
  end

  def down, do: :ok

  defp migrate_action_config(%{"target_kind" => "all_groups"} = action_config, metadata) do
    target_ids =
      metadata
      |> Map.get("control_groups", [])
      |> Enum.map(&Map.get(&1, "id"))
      |> normalize_target_ids()

    migrate_group_target(action_config, target_ids)
  end

  defp migrate_action_config(%{"target_kind" => "control_group"} = action_config, _metadata) do
    target_ids =
      action_config
      |> Map.get("control_group_id", Map.get(action_config, "target_id"))
      |> List.wrap()
      |> normalize_target_ids()

    migrate_group_target(action_config, target_ids)
  end

  defp migrate_action_config(%{"target_kind" => "control_groups"} = action_config, _metadata) do
    target_ids =
      action_config
      |> Map.get("target_ids", [])
      |> normalize_target_ids()

    migrate_group_target(action_config, target_ids)
  end

  defp migrate_action_config(_action_config, _metadata), do: :noop

  defp migrate_group_target(action_config, []), do: :clear_binding

  defp migrate_group_target(action_config, target_ids) do
    {:ok,
     action_config
     |> Map.put("target_kind", "control_groups")
     |> Map.put("target_ids", target_ids)
     |> Map.delete("target_id")
     |> Map.delete("control_group_id")}
  end

  defp normalize_target_ids(target_ids) do
    target_ids
    |> List.wrap()
    |> Enum.map(fn
      id when is_binary(id) ->
        case String.trim(id) do
          "" -> nil
          trimmed -> trimmed
        end

      id when is_atom(id) ->
        Atom.to_string(id)

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp decode_json(nil), do: %{}
  defp decode_json(value) when is_map(value), do: value

  defp decode_json(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _ -> %{}
    end
  end

  defp decode_json(_value), do: %{}
end
