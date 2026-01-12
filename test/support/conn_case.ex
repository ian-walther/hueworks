defmodule HueworksWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import HueworksWeb.ConnCase

      alias HueworksWeb.Router.Helpers, as: Routes

      @endpoint HueworksWeb.Endpoint
    end
  end

  setup tags do
    Hueworks.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
