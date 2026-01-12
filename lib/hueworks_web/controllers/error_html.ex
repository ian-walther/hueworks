defmodule HueworksWeb.ErrorHTML do
  def render("404.html", _assigns) do
    "Page not found"
  end

  def render("500.html", _assigns) do
    "Internal server error"
  end
end
