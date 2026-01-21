defmodule Hueworks.Bridges.Seed do
  @moduledoc false

  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge

  def seed! do
    load_secrets()
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    bridges = [
      %{
        type: :hue,
        name: "Upstairs Bridge",
        host: "192.168.1.162",
        credentials: %{
          "api_key" => fetch_env!("HUE_API_KEY")
        },
        enabled: true,
        import_complete: false,
        inserted_at: now,
        updated_at: now
      },
      %{
        type: :hue,
        name: "Downstairs Bridge",
        host: "192.168.1.224",
        credentials: %{
          "api_key" => fetch_env!("HUE_API_KEY_DOWNSTAIRS")
        },
        enabled: true,
        import_complete: false,
        inserted_at: now,
        updated_at: now
      },
      %{
        type: :caseta,
        name: "Caseta Bridge",
        host: "192.168.1.123",
        credentials: %{
          "cert_path" => fetch_env!("LUTRON_CERT_PATH"),
          "key_path" => fetch_env!("LUTRON_KEY_PATH"),
          "cacert_path" => fetch_env!("LUTRON_CACERT_PATH")
        },
        enabled: true,
        import_complete: false,
        inserted_at: now,
        updated_at: now
      },
      %{
        type: :ha,
        name: "Home Assistant",
        host: "192.168.1.41",
        credentials: %{
          "token" => fetch_env!("HA_TOKEN")
        },
        enabled: true,
        import_complete: false,
        inserted_at: now,
        updated_at: now
      }
    ]

    Repo.insert_all(
      Bridge,
      bridges,
      on_conflict: {:replace, [:name, :credentials, :enabled, :import_complete, :updated_at]},
      conflict_target: [:type, :host]
    )
  end

  defp load_secrets do
    if File.exists?("secrets.env") do
      "secrets.env"
      |> File.stream!()
      |> Stream.map(&String.trim/1)
      |> Enum.each(fn line ->
        cond do
          line == "" ->
            :ok

          String.starts_with?(line, "#") ->
            :ok

          String.starts_with?(line, "export ") ->
            line
            |> String.trim_leading("export ")
            |> String.split("=", parts: 2)
            |> put_env_from_parts()

          true ->
            line
            |> String.split("=", parts: 2)
            |> put_env_from_parts()
        end
      end)
    end
  end

  defp put_env_from_parts([key, value]) do
    value = value |> String.trim() |> String.trim("\"")
    System.put_env(key, value)
  end

  defp put_env_from_parts(_), do: :ok

  defp fetch_env!(key) do
    case System.get_env(key) do
      nil -> raise "Missing #{key}. Populate secrets.env and re-run mix seed_bridges."
      "" -> raise "Missing #{key}. Populate secrets.env and re-run mix seed_bridges."
      "CHANGE_ME" -> raise "Missing #{key}. Populate secrets.env and re-run mix seed_bridges."
      value -> value
    end
  end
end
