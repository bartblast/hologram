defmodule HologramClusterTestsWeb.Router do
  use Phoenix.Router

  get "/external", HologramClusterTestsWeb.ExternalController, :index
end
