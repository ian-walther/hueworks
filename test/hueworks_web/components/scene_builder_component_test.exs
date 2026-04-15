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
    |> form("form[phx-change='select_group'][data-component-id='1']", %{"group_id" => "10"})
    |> render_change()

    view
    |> element("button[phx-click='add_group'][phx-value-component_id='1']")
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

    view
    |> element("button[phx-click='add_light'][phx-value-component_id='1']")
    |> render_click()

    assert render(view) =~ "Unassigned lights: 1"

    view
    |> form("form[phx-change='select_light'][data-component-id='1']", %{"light_id" => "2"})
    |> render_change()

    view
    |> element("button[phx-click='add_light'][phx-value-component_id='1']")
    |> render_click()

    assert render(view) =~ "All lights assigned."
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

  test "dropdown only shows saved states and a blank option", %{conn: conn} do
    {:ok, state} = Scenes.create_manual_light_state("Soft", %{"brightness" => "40"})

    {:ok, view, _html} = live_isolated(conn, TestLive)
    html = render(view)

    assert has_element?(
             view,
             "select[name='light_state_id'] option[value=''][selected]",
             "Select light state"
           )

    assert html =~ ~s(option value="#{state.id}")
    refute html =~ ~s(option value="new")
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

  test "missing light state defaults to a blank selection", %{conn: conn} do
    {:ok, view, _html} =
      live_isolated(conn, ComponentStateLive, session: %{"state_id" => "123"})

    assert has_element?(
             view,
             "select[name='light_state_id'] option[value=''][selected]",
             "Select light state"
           )
  end
end
