defmodule Hueworks.Picos.Clone do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Picos
  alias Hueworks.Picos.Bindings
  alias Hueworks.Picos.ControlGroups
  alias Hueworks.Repo
  alias Hueworks.Schemas.{PicoButton, PicoDevice}

  def clone_device_config(%PicoDevice{} = destination, %PicoDevice{} = source) do
    destination = Picos.get_device(destination.id)
    source = Picos.get_device(source.id)

    cond do
      is_nil(destination) or is_nil(source) ->
        {:error, :device_not_found}

      destination.id == source.id ->
        {:error, :same_device}

      destination.bridge_id != source.bridge_id ->
        {:error, :different_bridge}

      not is_integer(source.room_id) ->
        {:error, :missing_source_room}

      true ->
        cloned_groups = ControlGroups.clone_for_copy(source)
        group_id_map = Map.new(cloned_groups, &{&1["source_id"], &1["id"]})

        Repo.transaction(fn ->
          destination
          |> PicoDevice.changeset(%{room_id: source.room_id})
          |> Repo.update!()

          update_device_metadata!(destination, fn metadata ->
            metadata
            |> Map.put("control_groups", Enum.map(cloned_groups, &Map.drop(&1, ["source_id"])))
            |> Map.put("room_override", true)
          end)

          destination_buttons =
            Repo.all(
              from(pb in PicoButton,
                where: pb.pico_device_id == ^destination.id
              )
            )

          source_buttons =
            Repo.all(
              from(pb in PicoButton,
                where: pb.pico_device_id == ^source.id
              )
            )

          source_by_button_number =
            Map.new(source_buttons, &{&1.button_number, &1})

          Enum.each(destination_buttons, fn destination_button ->
            source_button = Map.get(source_by_button_number, destination_button.button_number)

            attrs =
              case source_button do
                nil ->
                  %{action_type: nil, action_config: %{}, enabled: true}

                %PicoButton{} ->
                  %{
                    action_type: source_button.action_type,
                    action_config:
                      Bindings.clone_action_config(
                        PicoButton.action_config_struct(source_button),
                        group_id_map,
                        source.room_id
                      ),
                    enabled: source_button.enabled
                  }
              end

            destination_button
            |> PicoButton.changeset(attrs)
            |> Repo.update!()
          end)
        end)

        {:ok, Picos.get_device(destination.id)}
    end
  end

  defp update_device_metadata!(%PicoDevice{} = device, fun) when is_function(fun, 1) do
    device
    |> PicoDevice.changeset(%{metadata: fun.(device.metadata || %{})})
    |> Repo.update!()
  end
end
