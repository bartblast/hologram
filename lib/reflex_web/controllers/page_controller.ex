defmodule ReflexWeb.PageController do
  use ReflexWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
