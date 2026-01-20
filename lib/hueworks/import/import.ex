defmodule Hueworks.Import do
  @moduledoc false

  def import_hue_file(path), do: Hueworks.Legacy.Import.import_hue_file(path)
  def import_caseta_file(path), do: Hueworks.Legacy.Import.import_caseta_file(path)
  def import_home_assistant_file(path), do: Hueworks.Legacy.Import.import_home_assistant_file(path)

  def import_hue_data(data), do: Hueworks.Legacy.Import.import_hue_data(data)
  def import_caseta_data(data), do: Hueworks.Legacy.Import.import_caseta_data(data)
  def import_home_assistant_data(data), do: Hueworks.Legacy.Import.import_home_assistant_data(data)

  def import_from_files(files), do: Hueworks.Legacy.Import.import_from_files(files)
  def load_json(path), do: Hueworks.Legacy.Import.load_json(path)
end
