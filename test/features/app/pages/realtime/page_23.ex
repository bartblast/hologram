defmodule HologramFeatureTests.Realtime.Page23 do
  use Hologram.Page

  route "/realtime/23"

  layout HologramFeatureTests.Components.DefaultLayout

  # Dashboard landing page that the re-auth middleware redirects to. The
  # re-authenticated (user 2) tab lands here, so it can be reached by a
  # user-2-scoped broadcast - `:show` is defined so that stray delivery does not
  # dispatch an unknown action.
  def action(:show, _params, component), do: component

  def template do
    ~HOLO"""
    <h1>Dashboard</h1>
    """
  end
end
