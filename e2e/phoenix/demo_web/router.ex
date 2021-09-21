defmodule DemoWeb.Router do
  use DemoWeb, :router
  use Hologram.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/" do
    pipe_through :browser

    get "/", DemoWeb.PageController, :index

    hologram_routes()
  end
end
