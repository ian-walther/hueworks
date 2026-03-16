case Hueworks.BridgeSeeds.seed_from_file() do
  {:ok, count} ->
    Mix.shell().info("Seeded #{count} bridge entries from #{Hueworks.BridgeSeeds.default_path()}")

  {:error, {:missing_file, path}} ->
    Mix.raise("Missing #{path}. Create a JSON secrets file and re-run mix seed_bridges.")

  {:error, {:invalid_json, path, message}} ->
    Mix.raise("Invalid JSON in #{path}: #{message}")

  {:error, {:invalid_bridge_entry, index, reason}} ->
    Mix.raise("Invalid bridge entry at index #{index}: #{inspect(reason)}")

  {:error, {:invalid_bridge, attrs, changeset}} ->
    Mix.raise(
      "Invalid bridge seed #{inspect(attrs)}: #{inspect(Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end))}"
    )

  {:error, reason} ->
    Mix.raise("Failed to seed bridges: #{inspect(reason)}")
end
