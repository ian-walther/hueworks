defmodule Hueworks.SceneBuilderComponentTest do
  use HueworksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias Hueworks.Repo
  alias Hueworks.Scenes

  defmodule TestLive do
    use Phoenix.LiveView

    def mount(_params, _session, socket) do
      room_lights = [
        %{id: 1, name: "Lamp"},
        %{id: 2, name: "Ceiling"}
      ]

      groups = [
        %{id: 10, name: "All", light_ids: [1, 2]}
      ]

      light_states = Scenes.list_editable_light_states()

      {:ok, assign(socket, room_lights: room_lights, groups: groups, light_states: light_states)}
    end

    def render(assigns) do
      ~H"""
      <.live_component
        module={HueworksWeb.SceneBuilderComponent}
        id="scene-builder"
        room_lights={@room_lights}
        groups={@groups}
        light_states={@light_states}
      />
      """
    end
  end

  test "selecting and adding a light updates available options", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, TestLive)

    view
    |> form("form[phx-change='select_light'][data-component-id='1']", %{"light_id" => "1"})
    |> render_change()

    view
    |> element("button[phx-click='add_light'][phx-value-component_id='1']")
    |> render_click()

    html = render(view)

    assert html =~ "Lamp"
    refute html =~ "option value=\"1\">Lamp</option>"
  end

  test "adding a group assigns its lights and removes the group from options", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, TestLive)

    view
    |> form("form[phx-change='select_light'][data-component-id='1']", %{"light_id" => "2"})
    |> render_change()

    view
    |> element("button[phx-click='add_light'][phx-value-component_id='1']")
    |> render_click()

    html = render(view)

    assert html =~ "Lamp"
    assert html =~ "Ceiling"
    refute html =~ "option value=\"10\">All</option>"
  end

  test "removing a component returns lights to the available pool", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, TestLive)

    view
    |> form("form[phx-change='select_light'][data-component-id='1']", %{"light_id" => "1"})
    |> render_change()

    view
    |> element("button[phx-click='add_light'][phx-value-component_id='1']")
    |> render_click()

    html = render(view)
    refute html =~ "option value=\"1\">Lamp</option>"

    view
    |> element("button[phx-click='remove_component'][phx-value-component_id='1']")
    |> render_click()

    html = render(view)
    assert html =~ "option value=\"1\">Lamp</option>"
  end

  test "validation messages reflect unassigned lights as selections change", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, TestLive)

    html = render(view)
    assert html =~ "Unassigned lights: 2"

    view
    |> form("form[phx-change='select_light'][data-component-id='1']", %{"light_id" => "1"})
    |> render_change()

    view
    |> element("button[phx-click='add_light'][phx-value-component_id='1']")
    |> render_click()

    html = render(view)

    assert html =~ "Unassigned lights: 1"

    view
    |> form("form[phx-change='select_light'][data-component-id='1']", %{"light_id" => "2"})
    |> render_change()

    view
    |> element("button[phx-click='add_light'][phx-value-component_id='1']")
    |> render_click()

    html = render(view)

    assert html =~ "All lights assigned."
  end

  test "assigned light default power can be toggled in the component list", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, TestLive)

    view
    |> form("form[phx-change='select_light'][data-component-id='1']", %{"light_id" => "1"})
    |> render_change()

    view
    |> element("button[phx-click='add_light'][phx-value-component_id='1']")
    |> render_click()

    assert has_element?(
             view,
             "button[phx-click='toggle_light_default_power'][phx-value-component_id='1'][phx-value-light_id='1']",
             "Power policy: Force On"
           )

    view
    |> element(
      "button[phx-click='toggle_light_default_power'][phx-value-component_id='1'][phx-value-light_id='1']"
    )
    |> render_click()

    assert has_element?(
             view,
             "button[phx-click='toggle_light_default_power'][phx-value-component_id='1'][phx-value-light_id='1']",
             "Power policy: Force Off"
           )

    view
    |> element(
      "button[phx-click='toggle_light_default_power'][phx-value-component_id='1'][phx-value-light_id='1']"
    )
    |> render_click()

    assert has_element?(
             view,
             "button[phx-click='toggle_light_default_power'][phx-value-component_id='1'][phx-value-light_id='1']",
             "Power policy: Follow Occupancy"
           )
  end

  test "selecting a manual light state updates the component dropdown", %{conn: conn} do
    {:ok, state} = Scenes.create_manual_light_state("Soft")
    {:ok, view, _html} = live_isolated(conn, TestLive)

    view
    |> form("form[phx-change='select_light_state'][data-component-id='1']", %{
      "component_id" => "1",
      "light_state_id" => Integer.to_string(state.id)
    })
    |> render_change()

    html = render(view)

    assert html =~ "option value=\"#{state.id}\" selected"
    assert html =~ ~r/>\s*Soft \(manual\)\s*</
  end

  test "creating a manual light state adds it to the dropdown and selects it", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, TestLive)

    view
    |> form("form[phx-change='select_light_state'][data-component-id='1']", %{
      "component_id" => "1",
      "light_state_id" => "new"
    })
    |> render_change()

    view
    |> form("form[phx-change='select_light_state_name'][data-component-id='1']", %{
      "name" => "Warm"
    })
    |> render_change()

    view
    |> element("button[phx-click='save_light_state_name'][phx-value-component_id='1']")
    |> render_click()

    html = render(view)

    assert html =~ ~r/>\s*Warm \(manual\)\s*</
    assert html =~ "selected"
  end

  test "creating a manual light state with a blank name shows an error", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, TestLive)

    view
    |> form("form[phx-change='select_light_state'][data-component-id='1']", %{
      "component_id" => "1",
      "light_state_id" => "new"
    })
    |> render_change()

    view
    |> form("form[phx-change='select_light_state_name'][data-component-id='1']", %{"name" => ""})
    |> render_change()

    view
    |> element("button[phx-click='save_light_state_name'][phx-value-component_id='1']")
    |> render_click()

    html = render(view)

    assert html =~ "can&#39;t be blank"
  end

  test "editing a manual light state updates its config and warns about shared edits", %{
    conn: conn
  } do
    {:ok, state} = Scenes.create_manual_light_state("Soft")
    {:ok, view, _html} = live_isolated(conn, TestLive)

    view
    |> form("form[phx-change='select_light_state'][data-component-id='1']", %{
      "component_id" => "1",
      "light_state_id" => Integer.to_string(state.id)
    })
    |> render_change()

    view
    |> form("form[phx-change='update_light_state_form'][data-component-id='1']", %{
      "component_id" => "1",
      "brightness" => "42",
      "temperature" => "3200"
    })
    |> render_change()

    view
    |> element("button[phx-click='edit_light_state'][phx-value-component_id='1']")
    |> render_click()

    html = render(view)
    assert html =~ "Edits affect all scenes using this state."

    updated = Hueworks.Repo.get!(Hueworks.Schemas.LightState, state.id)
    assert updated.config["brightness"] == "42"
    assert updated.config["temperature"] == "3200"
  end

  test "duplicating a manual light state creates a new selectable copy", %{conn: conn} do
    {:ok, state} = Scenes.create_manual_light_state("Soft")
    {:ok, view, _html} = live_isolated(conn, TestLive)

    view
    |> form("form[phx-change='select_light_state'][data-component-id='1']", %{
      "light_state_id" => Integer.to_string(state.id)
    })
    |> render_change()

    view
    |> element("button[phx-click='duplicate_light_state'][phx-value-component_id='1']")
    |> render_click()

    html = render(view)
    assert html =~ "Soft Copy"
    assert html =~ "selected"
  end

  test "deleting a manual light state removes it from the dropdown", %{conn: conn} do
    {:ok, state} = Scenes.create_manual_light_state("Soft")
    {:ok, view, _html} = live_isolated(conn, TestLive)

    view
    |> form("form[phx-change='select_light_state'][data-component-id='1']", %{
      "component_id" => "1",
      "light_state_id" => Integer.to_string(state.id)
    })
    |> render_change()

    view
    |> element("button[phx-click='delete_light_state'][phx-value-component_id='1']")
    |> render_click()

    html = render(view)
    refute html =~ "Soft"
  end

  test "canonical lights and groups are excluded from dropdowns", %{conn: conn} do
    defmodule CanonicalLive do
      use Phoenix.LiveView

      def mount(_params, _session, socket) do
        room_lights = [
          %{id: 1, name: "Lamp"},
          %{id: 2, name: "Ceiling", canonical_light_id: 99}
        ]

        groups = [
          %{id: 10, name: "All", light_ids: [1, 2]},
          %{id: 11, name: "Work", light_ids: [1], canonical_group_id: 55}
        ]

        light_states = Hueworks.Scenes.list_editable_light_states()

        {:ok,
         assign(socket, room_lights: room_lights, groups: groups, light_states: light_states)}
      end

      def render(assigns) do
        ~H"""
        <.live_component
          module={HueworksWeb.SceneBuilderComponent}
          id="scene-builder"
          room_lights={@room_lights}
          groups={@groups}
          light_states={@light_states}
        />
        """
      end
    end

    {:ok, view, _html} = live_isolated(conn, CanonicalLive)
    html = render(view)

    assert html =~ "option value=\"1\">Lamp</option>"
    refute html =~ "option value=\"2\">Ceiling</option>"
    refute html =~ "option value=\"11\">Work</option>"
    assert html =~ "option value=\"10\">All</option>"
  end

  defmodule SliderInitLive do
    use Phoenix.LiveView

    def mount(_params, %{"state_id" => state_id}, socket) do
      room_lights = [%{id: 1, name: "Lamp"}]
      groups = []

      components = [
        %{id: 1, name: "Component 1", light_ids: [], group_ids: [], light_state_id: state_id}
      ]

      light_states = Hueworks.Scenes.list_editable_light_states()

      {:ok,
       assign(socket,
         room_lights: room_lights,
         groups: groups,
         components: components,
         light_states: light_states
       )}
    end

    def render(assigns) do
      ~H"""
      <.live_component
        module={HueworksWeb.SceneBuilderComponent}
        id="scene-builder"
        room_lights={@room_lights}
        groups={@groups}
        components={@components}
        light_states={@light_states}
      />
      """
    end
  end

  test "selected manual light state initializes slider values on render", %{conn: conn} do
    {:ok, state} = Scenes.create_manual_light_state("Soft")

    _ =
      Hueworks.Repo.update!(
        Ecto.Changeset.change(state, config: %{"brightness" => "55", "temperature" => "3000"})
      )

    {:ok, view, _html} =
      live_isolated(conn, SliderInitLive, session: %{"state_id" => to_string(state.id)})

    html = render(view)

    assert html =~ ~r/name=\"brightness\"[^>]*value=\"55\"/
    assert html =~ ~r/name=\"temperature\"[^>]*value=\"3000\"/
  end

  test "selected manual light state prepopulates name input on render", %{conn: conn} do
    {:ok, state} = Scenes.create_manual_light_state("Soft")
    _ = Hueworks.Repo.update!(Ecto.Changeset.change(state, config: %{"brightness" => "40"}))

    {:ok, view, _html} =
      live_isolated(conn, SliderInitLive, session: %{"state_id" => to_string(state.id)})

    html = render(view)

    assert html =~ ~r/name=\"name\"[^>]*value=\"Soft\"/
  end

  test "light and group dropdowns are hidden when no options remain", %{conn: conn} do
    defmodule NoOptionsLive do
      use Phoenix.LiveView

      def mount(_params, _session, socket) do
        room_lights = [%{id: 1, name: "Lamp"}, %{id: 2, name: "Ceiling"}]
        groups = [%{id: 10, name: "All", light_ids: [1, 2]}]

        components = [
          %{id: 1, name: "Component 1", light_ids: [1, 2], group_ids: [10], light_state_id: "new"}
        ]

        {:ok,
         assign(socket,
           room_lights: room_lights,
           groups: groups,
           components: components,
           light_states: []
         )}
      end

      def render(assigns) do
        ~H"""
        <.live_component
          module={HueworksWeb.SceneBuilderComponent}
          id="scene-builder"
          room_lights={@room_lights}
          groups={@groups}
          components={@components}
          light_states={@light_states}
        />
        """
      end
    end

    {:ok, view, _html} = live_isolated(conn, NoOptionsLive)

    refute has_element?(view, "label", "Add light")
    refute has_element?(view, "label", "Add group")
  end

  test "adding a group only adds room lights from that group", %{conn: conn} do
    defmodule MixedGroupLive do
      use Phoenix.LiveView

      def mount(_params, _session, socket) do
        room_lights = [%{id: 1, name: "Lamp"}, %{id: 2, name: "Ceiling"}]
        groups = [%{id: 10, name: "Mixed", light_ids: [2, 9]}]

        {:ok,
         assign(socket,
           room_lights: room_lights,
           groups: groups,
           light_states: []
         )}
      end

      def render(assigns) do
        ~H"""
        <.live_component
          module={HueworksWeb.SceneBuilderComponent}
          id="scene-builder"
          room_lights={@room_lights}
          groups={@groups}
          light_states={@light_states}
        />
        """
      end
    end

    {:ok, view, _html} = live_isolated(conn, MixedGroupLive)

    view
    |> form("form[phx-change='select_group'][data-component-id='1']", %{"group_id" => "10"})
    |> render_change()

    view
    |> element("button[phx-click='add_group'][phx-value-component_id='1']")
    |> render_click()

    html = render(view)

    assert html =~ "Ceiling"
    refute html =~ "Light 9"
  end

  test "save state button renames the selected light state", %{conn: conn} do
    {:ok, state} = Scenes.create_manual_light_state("Soft")

    {:ok, view, _html} =
      live_isolated(conn, SliderInitLive, session: %{"state_id" => to_string(state.id)})

    view
    |> form("form[phx-change='select_light_state_name'][data-component-id='1']", %{
      "name" => "Soft Renamed"
    })
    |> render_change()

    view
    |> element("button[phx-click='save_light_state_name'][phx-value-component_id='1']")
    |> render_click()

    html = render(view)

    assert html =~ "Soft Renamed"
    updated = Hueworks.Repo.get!(Hueworks.Schemas.LightState, state.id)
    assert updated.name == "Soft Renamed"
  end

  test "light state shows an unsaved changes label when sliders are modified", %{conn: conn} do
    {:ok, state} =
      Scenes.create_manual_light_state("Soft", %{"brightness" => "10", "temperature" => "2500"})

    {:ok, view, _html} =
      live_isolated(conn, SliderInitLive, session: %{"state_id" => to_string(state.id)})

    view
    |> form("form[phx-change='update_light_state_form'][data-component-id='1']", %{
      "component_id" => "1",
      "brightness" => "42",
      "temperature" => "3200"
    })
    |> render_change()

    assert has_element?(view, ".hw-muted", "(unsaved changes)")

    view
    |> element("button[phx-click='save_light_state_name'][phx-value-component_id='1']")
    |> render_click()

    refute has_element?(view, ".hw-muted", "(unsaved changes)")
  end

  test "light state dropdown includes a New option", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, TestLive)
    html = render(view)

    assert html =~ ~r/option value=\"new\"/
  end

  test "new manual selection shows sliders and name input", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, TestLive)

    assert has_element?(view, "select[name='light_state_id'] option[value='new'][selected]")
    assert has_element?(view, "label", "Brightness")
    assert has_element?(view, "label", "Temperature")
    assert has_element?(view, "label", "Light state name")
    assert has_element?(view, "button", "Edit")
    assert has_element?(view, "button", "Duplicate")
    assert has_element?(view, "button", "Delete")
  end

  test "missing light state defaults to new manual and disables edit actions", %{conn: conn} do
    defmodule MissingStateLive do
      use Phoenix.LiveView

      def mount(_params, _session, socket) do
        room_lights = [%{id: 1, name: "Lamp"}]
        groups = []

        components = [
          %{id: 1, name: "Component 1", light_ids: [], group_ids: [], light_state_id: "123"}
        ]

        {:ok,
         assign(socket,
           room_lights: room_lights,
           groups: groups,
           components: components,
           light_states: []
         )}
      end

      def render(assigns) do
        ~H"""
        <.live_component
          module={HueworksWeb.SceneBuilderComponent}
          id="scene-builder"
          room_lights={@room_lights}
          groups={@groups}
          components={@components}
          light_states={@light_states}
        />
        """
      end
    end

    {:ok, view, _html} = live_isolated(conn, MissingStateLive)
    assert has_element?(view, "select[name='light_state_id'] option[value='new'][selected]")
    assert has_element?(view, "button[phx-click='edit_light_state'][disabled]")
    assert has_element?(view, "button[phx-click='duplicate_light_state'][disabled]")
    assert has_element?(view, "button[phx-click='delete_light_state'][disabled]")
  end

  test "selected circadian light state renders all circadian inputs", %{conn: conn} do
    {:ok, state} =
      Scenes.create_light_state("Circadian", :circadian, %{
        "brightness_mode" => "linear",
        "min_brightness" => 10,
        "max_brightness" => 80,
        "min_color_temp" => 2200,
        "max_color_temp" => 5000,
        "sunrise_time" => "06:30:00",
        "sunset_time" => "19:30:00",
        "sunrise_offset" => 0,
        "sunset_offset" => 0,
        "brightness_mode_time_dark" => 1200,
        "brightness_mode_time_light" => 3600
      })

    {:ok, view, _html} =
      live_isolated(conn, SliderInitLive, session: %{"state_id" => to_string(state.id)})

    assert has_element?(view, "select[name='brightness_mode']")

    for key <- [
          "min_brightness",
          "max_brightness",
          "min_color_temp",
          "max_color_temp",
          "sunrise_time",
          "min_sunrise_time",
          "max_sunrise_time",
          "sunrise_offset",
          "sunset_time",
          "min_sunset_time",
          "max_sunset_time",
          "sunset_offset",
          "brightness_mode_time_dark",
          "brightness_mode_time_light"
        ] do
      assert has_element?(view, "input[name='#{key}']")
    end
  end

  test "creating a circadian light state saves all circadian form fields", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, TestLive)

    view
    |> form("form[phx-change='select_light_state'][data-component-id='1']", %{
      "component_id" => "1",
      "light_state_id" => "new_circadian"
    })
    |> render_change()

    view
    |> form("form[phx-change='update_light_state_form'][data-component-id='1']", %{
      "component_id" => "1",
      "min_brightness" => "5",
      "max_brightness" => "95",
      "min_color_temp" => "2100",
      "max_color_temp" => "5000",
      "sunrise_time" => "06:30:00",
      "min_sunrise_time" => "05:45:00",
      "max_sunrise_time" => "07:00:00",
      "sunrise_offset" => "-900",
      "sunset_time" => "19:30:00",
      "min_sunset_time" => "18:45:00",
      "max_sunset_time" => "20:15:00",
      "sunset_offset" => "1200",
      "brightness_mode" => "linear",
      "brightness_mode_time_dark" => "1200",
      "brightness_mode_time_light" => "5400"
    })
    |> render_change()

    view
    |> form("form[phx-change='select_light_state_name'][data-component-id='1']", %{
      "name" => "Circadian A"
    })
    |> render_change()

    view
    |> element("button[phx-click='save_light_state_name'][phx-value-component_id='1']")
    |> render_click()

    state = Repo.get_by!(Hueworks.Schemas.LightState, name: "Circadian A")
    assert state.type == :circadian

    assert state.config["min_brightness"] == 5
    assert state.config["max_brightness"] == 95
    assert state.config["min_color_temp"] == 2100
    assert state.config["max_color_temp"] == 5000
    assert state.config["sunrise_time"] == "06:30:00"
    assert state.config["min_sunrise_time"] == "05:45:00"
    assert state.config["max_sunrise_time"] == "07:00:00"
    assert state.config["sunrise_offset"] == -900
    assert state.config["sunset_time"] == "19:30:00"
    assert state.config["min_sunset_time"] == "18:45:00"
    assert state.config["max_sunset_time"] == "20:15:00"
    assert state.config["sunset_offset"] == 1200
    assert state.config["brightness_mode"] == "linear"
    assert state.config["brightness_mode_time_dark"] == 1200
    assert state.config["brightness_mode_time_light"] == 5400
  end
end
