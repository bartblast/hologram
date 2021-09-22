defmodule Hologram.E2E.Web.Router do
  use Hologram.E2E.Web, :router
  use Hologram.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {Hologram.E2E.Web.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/" do
    hologram_routes()
  end
end
