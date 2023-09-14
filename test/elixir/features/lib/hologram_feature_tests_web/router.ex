defmodule HologramFeatureTestsWeb.Router do
  use HologramFeatureTestsWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", HologramFeatureTestsWeb do
    pipe_through :api
  end
end
