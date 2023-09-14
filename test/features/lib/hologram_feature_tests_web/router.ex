defmodule HologramFeatureTestsWeb.Router do
  use HologramFeatureTestsWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", HologramFeatureTestsWeb do
    pipe_through :api

    # This route is here only to prevent Dialyzer warning: "The pattern can never match the type.".
    # See: https://github.com/phoenixframework/phoenix/issues/5375
    get "/", PageController, :home
  end
end
