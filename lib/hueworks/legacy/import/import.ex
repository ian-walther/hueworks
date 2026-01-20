defmodule Hueworks.Legacy.Import do
  @moduledoc """
  Import orchestration for Hue, Caseta, and Home Assistant exports.
  """

  alias Hueworks.Legacy.Import.{Caseta, HomeAssistant, Hue}

  def import_hue_file(path) do
    path |> load_json() |> import_hue_data()
  end

  def import_caseta_file(path) do
    path |> load_json() |> import_caseta_data()
  end

  def import_home_assistant_file(path) do
    path |> load_json() |> import_home_assistant_data()
  end

  def import_hue_data(data) do
    Hue.import(data)
  end

  def import_caseta_data(data) do
    Caseta.import(data)
  end

  def import_home_assistant_data(data) do
    HomeAssistant.import(data)
  end

  def import_from_files(%{hue: hue_path, caseta: caseta_path, ha: ha_path}) do
    %{
      hue: import_hue_file(hue_path),
      caseta: import_caseta_file(caseta_path),
      home_assistant: import_home_assistant_file(ha_path)
    }
  end

  def load_json(path) do
    path
    |> File.read!()
    |> Jason.decode!()
  end
end
