defmodule Hueworks.Control.Bootstrap.Caseta do
  @moduledoc false

  alias Hueworks.Control.Bootstrap.Observations
  alias Hueworks.Control.{CasetaLeap, Indexes, StateParser}
  alias Hueworks.Schemas.Bridge

  def run(%Bridge{} = bridge, opts \\ []) do
    ssl = Keyword.get(opts, :ssl_module, :ssl)
    lights = Observations.capture(:light, Indexes.lights_by_source_id(bridge.id, :caseta))

    with :ok <- Hueworks.RuntimeIO.ensure_enabled(),
         {:ok, socket} <- CasetaLeap.connect(bridge, ssl) do
      try do
        request = %{"CommuniqueType" => "ReadRequest", "Header" => %{"Url" => "/zone/status"}}

        with :ok <- CasetaLeap.set_socket_opts(ssl, socket),
             :ok <- CasetaLeap.send_request(ssl, socket, request),
             {:ok, decoded} <-
               CasetaLeap.read_until_match(ssl, socket, "/zone/status", 5_000, :message),
             {:ok, zones} <- zone_statuses(decoded) do
          Enum.each(zones, fn zone ->
            source_id =
              zone |> get_in(["Zone", "href"]) |> to_string() |> String.split("/") |> List.last()

            if entry = Map.get(lights, source_id) do
              attrs =
                Map.merge(
                  StateParser.brightness_from_0_100(zone["Level"]),
                  StateParser.power_from_level(zone["Level"])
                )

              Observations.put(:light, entry, attrs)
            end
          end)

          :ok
        end
      after
        ssl.close(socket)
      end
    end
  end

  defp zone_statuses(%{"Body" => %{"ZoneStatuses" => zones}}) when is_list(zones),
    do: {:ok, zones}

  defp zone_statuses(%{"Body" => %{"ZoneStatus" => zones}}) when is_list(zones), do: {:ok, zones}
  defp zone_statuses(%{"Body" => %{"ZoneStatus" => zone}}) when is_map(zone), do: {:ok, [zone]}
  defp zone_statuses(_), do: {:error, :invalid_response}
end
