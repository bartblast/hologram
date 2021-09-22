defmodule Hologram.E2E.Web.Router do
  use Hologram.E2E.Web, :router
  use Hologram.Router

  scope "/" do
    hologram_routes()
  end
end
