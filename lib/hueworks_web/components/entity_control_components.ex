defmodule HueworksWeb.EntityControlComponents do
  use Phoenix.Component

  alias Hueworks.Kelvin
  alias HueworksWeb.LightsLive.Presentation

  attr(:target, :any, required: true)
  attr(:target_type, :atom, required: true, values: [:light, :group])
  attr(:state_map, :map, required: true)
  attr(:variant, :atom, default: :inline, values: [:inline, :modal])
  attr(:disabled, :boolean, default: false)

  def controls(assigns) do
    type = Atom.to_string(assigns.target_type)
    ids = control_ids(type, assigns.target.id, assigns.variant)

    assigns =
      assigns
      |> assign(:type, type)
      |> assign(:ids, ids)
      |> assign(
        :brightness,
        Presentation.state_value(assigns.state_map, assigns.target.id, :brightness, 75)
      )
      |> assign(:color_preview, Presentation.color_preview(assigns.state_map, assigns.target.id))

    ~H"""
    <div class={["hw-control-surface", "hw-control-surface-#{@variant}"]}>
      <.slider
        id={@ids.brightness}
        label_id={@ids.brightness_label}
        value_id={@ids.brightness_value}
        label="Brightness"
        value={@brightness}
        suffix="%"
        min={1}
        max={100}
        hook="BrightnessSlider"
        type={@type}
        target_id={@target.id}
        disabled={@disabled}
        variant={@variant}
      />

      <%= if @target.supports_temp do %>
        <% {min_k, max_k} = Kelvin.derive_range(@target) %>
        <% kelvin = Presentation.state_value(@state_map, @target.id, :kelvin, round((min_k + max_k) / 2)) %>
        <.slider
          id={@ids.temp}
          label_id={@ids.temp_label}
          value_id={@ids.temp_value}
          label="Temperature"
          value={kelvin}
          suffix="K"
          min={min_k}
          max={max_k}
          hook="TempSlider"
          type={@type}
          target_id={@target.id}
          disabled={@disabled}
          variant={@variant}
        />
      <% end %>

      <%= if @target.supports_color do %>
        <div class="hw-color-preview">
          <span
            class="hw-color-swatch"
            style={Presentation.color_preview_style(@state_map, @target.id)}
          >
          </span>
          <span class="hw-muted"><%= Presentation.color_preview_label(@state_map, @target.id) %></span>
        </div>

        <.slider
          id={@ids.hue}
          label_id={@ids.hue_label}
          value_id={@ids.hue_value}
          label="Hue"
          value={@color_preview.hue}
          suffix="°"
          min={0}
          max={360}
          hook="ColorHueSlider"
          type={@type}
          target_id={@target.id}
          disabled={@disabled}
          variant={@variant}
          hue_id={@ids.hue}
          saturation_id={@ids.saturation}
        />
        <div class="hw-color-scale hw-hue-scale" aria-hidden="true"></div>

        <.slider
          id={@ids.saturation}
          label_id={@ids.saturation_label}
          value_id={@ids.saturation_value}
          label="Saturation"
          value={@color_preview.saturation}
          suffix="%"
          min={0}
          max={100}
          hook="ColorSaturationSlider"
          type={@type}
          target_id={@target.id}
          disabled={@disabled}
          variant={@variant}
          hue_id={@ids.hue}
          saturation_id={@ids.saturation}
        />
        <div
          class="hw-color-scale"
          style={Presentation.color_saturation_scale_style(@state_map, @target.id)}
          aria-hidden="true"
        >
        </div>
      <% end %>
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:label_id, :string, required: true)
  attr(:value_id, :string, required: true)
  attr(:label, :string, required: true)
  attr(:value, :integer, required: true)
  attr(:suffix, :string, required: true)
  attr(:min, :integer, required: true)
  attr(:max, :integer, required: true)
  attr(:hook, :string, required: true)
  attr(:type, :string, required: true)
  attr(:target_id, :integer, required: true)
  attr(:disabled, :boolean, required: true)
  attr(:variant, :atom, required: true)
  attr(:hue_id, :string, default: nil)
  attr(:saturation_id, :string, default: nil)

  defp slider(assigns) do
    ~H"""
    <div class={if @variant == :modal, do: "hw-control-slider", else: "hw-slider"}>
      <div :if={@variant == :modal} class="hw-control-slider-label">
        <span id={@label_id}><%= @label %></span>
        <span id={@value_id} class="hw-slider-value"><%= @value %><%= @suffix %></span>
      </div>
      <input
        id={@id}
        type="range"
        min={@min}
        max={@max}
        value={@value}
        phx-hook={@hook}
        data-type={@type}
        data-id={@target_id}
        data-output-id={@value_id}
        data-hue-input-id={@hue_id}
        data-saturation-input-id={@saturation_id}
        disabled={@disabled}
      />
      <span :if={@variant == :inline} id={@label_id}><%= @label %></span>
      <span :if={@variant == :inline} id={@value_id} class="hw-slider-value">
        <%= @value %><%= @suffix %>
      </span>
    </div>
    """
  end

  defp control_ids(type, id, :inline) do
    %{
      brightness: "#{type}-level-#{id}",
      brightness_label: "#{type}-brightness-label-#{id}",
      brightness_value: "#{type}-brightness-value-#{id}",
      temp: "#{type}-temp-#{id}",
      temp_label: "#{type}-temp-label-#{id}",
      temp_value: "#{type}-temp-value-#{id}",
      hue: "#{type}-hue-#{id}",
      hue_label: "#{type}-hue-label-#{id}",
      hue_value: "#{type}-hue-value-#{id}",
      saturation: "#{type}-saturation-#{id}",
      saturation_label: "#{type}-saturation-label-#{id}",
      saturation_value: "#{type}-saturation-value-#{id}"
    }
  end

  defp control_ids(type, id, :modal) do
    prefix = "control-#{type}"

    %{
      brightness: "#{prefix}-brightness-#{id}",
      brightness_label: "#{prefix}-brightness-label-#{id}",
      brightness_value: "#{prefix}-brightness-value-#{id}",
      temp: "#{prefix}-temp-#{id}",
      temp_label: "#{prefix}-temp-label-#{id}",
      temp_value: "#{prefix}-temp-value-#{id}",
      hue: "#{prefix}-hue-#{id}",
      hue_label: "#{prefix}-hue-label-#{id}",
      hue_value: "#{prefix}-hue-value-#{id}",
      saturation: "#{prefix}-saturation-#{id}",
      saturation_label: "#{prefix}-saturation-label-#{id}",
      saturation_value: "#{prefix}-saturation-value-#{id}"
    }
  end
end
