defmodule HueworksWeb.LightsLive.EditFlow do
  @moduledoc false

  alias HueworksWeb.LightsLive.Editor
  alias Hueworks.Util

  def open(type, id) do
    case Editor.open_assigns(type, id) do
      {:ok, modal_assigns} -> {:ok, modal_assigns}
      {:error, reason} -> {:error, "ERROR #{type} #{id}: #{Util.format_reason(reason)}"}
    end
  end

  def close, do: Editor.default_assigns()

  def show_link_selector do
    %{edit_show_link_selector: true}
  end

  def update(assigns, params) when is_map(assigns) and is_map(params) do
    Editor.update_assigns(assigns, params)
  end

  def run("open_edit", %{"type" => type, "id" => id}, _assigns, _reload_fun) do
    open(type, id)
  end

  def run("close_edit", _params, _assigns, _reload_fun) do
    {:ok, close()}
  end

  def run("show_link_selector", _params, _assigns, _reload_fun) do
    {:ok, show_link_selector()}
  end

  def run("update_display_name", %{"display_name" => display_name}, assigns, _reload_fun) do
    {:ok, update(assigns, %{"display_name" => display_name})}
  end

  def run("update_edit_fields", params, assigns, _reload_fun) do
    {:ok, update(assigns, params)}
  end

  def run("save_display_name", %{"display_name" => display_name}, assigns, reload_fun) do
    save(assigns, %{"display_name" => display_name}, reload_fun)
  end

  def run("save_edit_fields", params, assigns, reload_fun) do
    save(assigns, params, reload_fun)
  end

  def save(assigns, params, reload_fun)
      when is_map(assigns) and is_map(params) and is_function(reload_fun, 1) do
    type = assigns.edit_target_type
    id = assigns.edit_target_id

    with {:ok, updated} <- Editor.save(type, id, params) do
      updates =
        assigns
        |> reload_fun.()
        |> Map.merge(close())
        |> Map.put(:status, "Saved #{type} #{Util.display_name(updated)}")

      {:ok, updates}
    else
      {:error, reason} ->
        {:error, "ERROR #{type} #{id}: #{Util.format_reason(reason)}"}
    end
  end
end
