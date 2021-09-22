defmodule HologramWeb.PageController do
  use HologramWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
