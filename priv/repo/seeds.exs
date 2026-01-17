alias Hueworks.Bridges.Bridge
alias Hueworks.Repo

if File.exists?("secrets.env") do
  "secrets.env"
  |> File.stream!()
  |> Stream.map(&String.trim/1)
  |> Enum.each(fn line ->
    cond do
      line == "" -> :ok
      String.starts_with?(line, "#") -> :ok
      String.starts_with?(line, "export ") ->
        line
        |> String.trim_leading("export ")
        |> String.split("=", parts: 2)
        |> then(fn
          [key, value] ->
            value = value |> String.trim() |> String.trim("\"")
            System.put_env(key, value)

          _ ->
            :ok
        end)

      true ->
        case String.split(line, "=", parts: 2) do
          [key, value] ->
            value = value |> String.trim() |> String.trim("\"")
            System.put_env(key, value)

          _ ->
            :ok
        end
    end
  end)
end

now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

fetch_env! = fn key ->
  value = System.get_env(key)

  case value do
    nil -> raise "Missing #{key}. Populate secrets.env and re-run seeds."
    "" -> raise "Missing #{key}. Populate secrets.env and re-run seeds."
    "CHANGE_ME" -> raise "Missing #{key}. Populate secrets.env and re-run seeds."
    _ -> value
  end
end

bridges = [
  %{
    type: :hue,
    name: "Upstairs Bridge",
    host: "192.168.1.162",
    credentials: %{
      "api_key" => fetch_env!.("HUE_API_KEY")
    },
    enabled: true,
    inserted_at: now,
    updated_at: now
  },
  %{
    type: :hue,
    name: "Downstairs Bridge",
    host: "192.168.1.224",
    credentials: %{
      "api_key" => fetch_env!.("HUE_API_KEY_DOWNSTAIRS")
    },
    enabled: true,
    inserted_at: now,
    updated_at: now
  },
  %{
    type: :caseta,
    name: "Caseta Bridge",
    host: "192.168.1.123",
    credentials: %{
      "cert_path" => fetch_env!.("LUTRON_CERT_PATH"),
      "key_path" => fetch_env!.("LUTRON_KEY_PATH"),
      "cacert_path" => fetch_env!.("LUTRON_CACERT_PATH")
    },
    enabled: true,
    inserted_at: now,
    updated_at: now
  },
  %{
    type: :ha,
    name: "Home Assistant",
    host: "192.168.1.41",
    credentials: %{
      "token" => fetch_env!.("HA_TOKEN")
    },
    enabled: true,
    inserted_at: now,
    updated_at: now
  }
]

Repo.insert_all(
  Bridge,
  bridges,
  on_conflict: {:replace, [:name, :credentials, :enabled, :updated_at]},
  conflict_target: [:type, :host]
)
