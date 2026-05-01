defmodule Hueworks.SceneBuilderComponentTest do
  use HueworksWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Hueworks.Repo
  alias Hueworks.Scenes
  alias Hueworks.Schemas.LightState

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

      {:ok,
       assign(socket,
         room_lights: room_lights,
         groups: groups,
         light_states: Scenes.list_editable_light_states()
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

  defmodule ComponentStateLive do
    use Phoenix.LiveView

    def mount(_params, %{"state_id" => state_id}, socket) do
      room_lights = [%{id: 1, name: "Lamp"}]

      components = [
        %{id: 1, name: "Component 1", light_ids: [], group_ids: [], light_state_id: state_id}
      ]

      {:ok,
       assign(socket,
         room_lights: room_lights,
         groups: [],
         components: components,
         light_states: Scenes.list_editable_light_states()
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

  test "selecting a light auto-adds it and updates available options", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, TestLive)

    view
    |> form("form[phx-change='select_light'][data-component-id='1']", %{"light_id" => "1"})
    |> render_change()

    html = render(view)
    assert html =~ "Lamp"
    refute html =~ "option value=\"1\">Lamp</option>"
  end

  test "selecting a group auto-adds its lights and removes the group from options", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, TestLive)

    view
    |> form("form[phx-change='select_group'][data-component-id='1']", %{"group_id" => "10"})
    |> render_change()

    view
    |> element(
      "button[phx-click='toggle_group_expanded'][phx-value-component_id='1'][phx-value-group_id='10']"
    )
    |> render_click()

    html = render(view)
    assert html =~ "Lamp"
    assert html =~ "Ceiling"
    refute html =~ "option value=\"10\">All</option>"
  end

  test "assigned groups can be removed as a shortcut for removing all group lights", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, TestLive)

    view
    |> form("form[phx-change='select_group'][data-component-id='1']", %{"group_id" => "10"})
    |> render_change()

    view
    |> element(
      "button[phx-click='toggle_group_expanded'][phx-value-component_id='1'][phx-value-group_id='10']"
    )
    |> render_click()

    assert render(view) =~ "Lamp"
    assert render(view) =~ "Ceiling"

    view
    |> element(
      "button[phx-click='remove_group'][phx-value-component_id='1'][phx-value-group_id='10']"
    )
    |> render_click()

    html = render(view)
    assert html =~ "No lights assigned"
    assert html =~ "option value=\"10\">All</option>"
  end

  test "assigned strict subset groups render collapsed by default and expand with grouped lights",
       %{conn: conn} do
    defmodule NestedGroupLive do
      use Phoenix.LiveView

      def mount(_params, _session, socket) do
        {:ok,
         assign(socket,
           room_lights: [
             %{id: 1, name: "Upper Left"},
             %{id: 2, name: "Upper Right"},
             %{id: 3, name: "Lower Left"},
             %{id: 4, name: "Loose Lamp"}
           ],
           groups: [
             %{id: 10, name: "All Cabinet", light_ids: [1, 2, 3]},
             %{id: 11, name: "Upper Cabinet", light_ids: [1, 2]},
             %{id: 12, name: "Left Cabinet", light_ids: [1, 3]}
           ],
           components: [
             %{
               id: 1,
               name: "Component 1",
               light_ids: [1, 2, 3, 4],
               group_ids: [],
               light_state_id: nil,
               light_defaults: %{}
             }
           ],
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

    {:ok, view, _html} = live_isolated(conn, NestedGroupLive)

    assert has_element?(view, "#scene-component-1-group-10")
    refute has_element?(view, "#scene-component-1-group-10 #scene-component-1-group-11")
    refute has_element?(view, "#scene-component-1-group-10-light-1")

    view
    |> element(
      "button[phx-click='toggle_group_expanded'][phx-value-component_id='1'][phx-value-group_id='10']"
    )
    |> render_click()

    assert has_element?(view, "#scene-component-1-group-10 #scene-component-1-group-11")
    assert has_element?(view, "#scene-component-1-group-10 #scene-component-1-group-12")
    refute has_element?(view, "#scene-component-1-group-10-light-1")

    view
    |> element(
      "button[phx-click='toggle_group_expanded'][phx-value-component_id='1'][phx-value-group_id='11']"
    )
    |> render_click()

    assert has_element?(view, "#scene-component-1-group-11-light-1")

    assert has_element?(
             view,
             "#scene-component-1-group-11-light-1 button[phx-click='toggle_light_default_power'][phx-value-component_id='1'][phx-value-light_id='1']"
           )

    assert has_element?(
             view,
             "#scene-component-1-group-11-light-1 button[phx-click='remove_light'][phx-value-component_id='1'][phx-value-light_id='1']"
           )

    assert has_element?(
             view,
             "button[phx-click='remove_light'][phx-value-component_id='1'][phx-value-light_id='4']"
           )

    view
    |> element(
      "button[phx-click='toggle_group_expanded'][phx-value-component_id='1'][phx-value-group_id='10']"
    )
    |> render_click()

    refute has_element?(view, "#scene-component-1-group-11-light-1")
  end

  test "removing a component returns lights to the available pool", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, TestLive)

    view
    |> form("form[phx-change='select_light'][data-component-id='1']", %{"light_id" => "1"})
    |> render_change()

    refute render(view) =~ "option value=\"1\">Lamp</option>"

    view
    |> element("button[phx-click='remove_component'][phx-value-component_id='1']")
    |> render_click()

    assert render(view) =~ "option value=\"1\">Lamp</option>"
  end

  test "validation messages reflect unassigned lights as selections change", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, TestLive)

    assert render(view) =~ "Unassigned lights: 2"

    view
    |> form("form[phx-change='select_light'][data-component-id='1']", %{"light_id" => "1"})
    |> render_change()

    assert render(view) =~ "Unassigned lights: 1"

    view
    |> form("form[phx-change='select_light'][data-component-id='1']", %{"light_id" => "2"})
    |> render_change()

    assert render(view) =~ "All lights assigned."
  end

  test "assigned light default power can be toggled in the component list", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, TestLive)

    view
    |> form("form[phx-change='select_light'][data-component-id='1']", %{"light_id" => "1"})
    |> render_change()

    assert has_element?(
             view,
             "button[phx-click='toggle_light_default_power'][phx-value-component_id='1'][phx-value-light_id='1']",
             "Power policy: Default On"
           )

    view
    |> element(
      "button[phx-click='toggle_light_default_power'][phx-value-component_id='1'][phx-value-light_id='1']"
    )
    |> render_click()

    assert has_element?(
             view,
             "button[phx-click='toggle_light_default_power'][phx-value-component_id='1'][phx-value-light_id='1']",
             "Power policy: Default Off"
           )
  end

  test "assigned groups show mixed state and can bulk-toggle member power policy", %{conn: conn} do
    defmodule GroupPolicyLive do
      use Phoenix.LiveView

      def mount(_params, _session, socket) do
        {:ok,
         assign(socket,
           room_lights: [%{id: 1, name: "Lamp"}, %{id: 2, name: "Ceiling"}],
           groups: [%{id: 10, name: "All", light_ids: [1, 2]}],
           components: [
             %{
               id: 1,
               name: "Component 1",
               light_ids: [1, 2],
               group_ids: [10],
               light_state_id: nil,
               light_defaults: %{1 => :force_on, 2 => :force_off}
             }
           ],
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

    {:ok, view, _html} = live_isolated(conn, GroupPolicyLive)

    assert has_element?(
             view,
             "button[phx-click='toggle_group_default_power'][phx-value-component_id='1'][phx-value-group_id='10']",
             "Power policy: ..."
           )

    view
    |> element(
      "button[phx-click='toggle_group_default_power'][phx-value-component_id='1'][phx-value-group_id='10']"
    )
    |> render_click()

    assert has_element?(
             view,
             "button[phx-click='toggle_group_default_power'][phx-value-component_id='1'][phx-value-group_id='10']",
             "Power policy: Default On"
           )
  end

  test "canonical lights and groups are excluded from dropdowns", %{conn: conn} do
    defmodule CanonicalLive do
      use Phoenix.LiveView

      def mount(_params, _session, socket) do
        {:ok,
         assign(socket,
           room_lights: [
             %{id: 1, name: "Lamp"},
             %{id: 2, name: "Ceiling", canonical_light_id: 99}
           ],
           groups: [
             %{id: 10, name: "All", light_ids: [1, 2]},
             %{id: 11, name: "Work", light_ids: [1], canonical_group_id: 55}
           ],
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

    {:ok, view, _html} = live_isolated(conn, CanonicalLive)
    html = render(view)

    assert html =~ "option value=\"1\">Lamp</option>"
    refute html =~ "option value=\"2\">Ceiling</option>"
    refute html =~ "option value=\"11\">Work</option>"
    assert html =~ "option value=\"10\">All</option>"
  end

  test "dropdown shows saved states plus custom options", %{conn: conn} do
    {:ok, state} = Scenes.create_manual_light_state("Soft", %{"brightness" => "40"})

    {:ok, view, _html} = live_isolated(conn, TestLive)
    html = render(view)

    assert has_element?(
             view,
             "select[name='light_state_id'] option[value=''][selected]",
             "Select light state"
           )

    assert html =~ ~s(option value="#{state.id}")
    assert html =~ ~s(option value="custom")
    assert html =~ ~s(option value="custom_color")
    refute html =~ "Light state name"
    refute html =~ "Edit"
    refute html =~ "Duplicate"
    refute html =~ "Delete"
  end

  test "manual color labels render for atom-keyed manual configs", %{conn: conn} do
    Repo.insert!(%LightState{
      name: "Blue",
      type: :manual,
      config: %{mode: :color, brightness: 75, hue: 210, saturation: 60}
    })

    {:ok, _view, html} = live_isolated(conn, TestLive)

    assert html =~ "Blue (manual color)"
  end

  test "selecting an existing light state updates the component dropdown", %{conn: conn} do
    {:ok, state} = Scenes.create_manual_light_state("Soft", %{"brightness" => "40"})
    {:ok, view, _html} = live_isolated(conn, TestLive)

    view
    |> form("form[phx-change='select_light_state'][data-component-id='1']", %{
      "component_id" => "1",
      "light_state_id" => Integer.to_string(state.id)
    })
    |> render_change()

    assert has_element?(
             view,
             "select[name='light_state_id'] option[value='#{state.id}'][selected]"
           )
  end

  test "selecting a custom light state shows inline manual controls", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, TestLive)

    view
    |> form("form[phx-change='select_light_state'][data-component-id='1']", %{
      "component_id" => "1",
      "light_state_id" => "custom"
    })
    |> render_change()

    assert has_element?(
             view,
             "select[name='light_state_id'] option[value='custom'][selected]",
             "Custom"
           )

    assert has_element?(view, "input[name='brightness']")
    assert has_element?(view, "input[name='temperature']")
    refute has_element?(view, "input[name='hue']")
  end

  test "selecting a custom color light state shows inline color controls", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, TestLive)

    view
    |> form("form[phx-change='select_light_state'][data-component-id='1']", %{
      "component_id" => "1",
      "light_state_id" => "custom_color"
    })
    |> render_change()

    assert has_element?(
             view,
             "select[name='light_state_id'] option[value='custom_color'][selected]",
             "Custom Color"
           )

    assert has_element?(view, "input[name='brightness']")
    assert has_element?(view, "input[name='hue']")
    assert has_element?(view, "input[name='saturation']")
    refute has_element?(view, "input[name='temperature']")
  end

  test "missing light state defaults to a blank selection", %{conn: conn} do
    {:ok, view, _html} =
      live_isolated(conn, ComponentStateLive, session: %{"state_id" => "123"})

    html = render(view)

    assert html =~ "Select light state"
    refute html =~ ~s(option value="123" selected)
  end
end
