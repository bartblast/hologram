defmodule HologramFeatureTestsWeb.Router do
  use Phoenix.Router

  get "/external", HologramFeatureTestsWeb.ExternalController, :index
end
