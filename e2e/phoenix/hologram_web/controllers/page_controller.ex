defmodule Hologram.E2E.Web.PageController do
  use Hologram.E2E.Web, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
