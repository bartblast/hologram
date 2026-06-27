defmodule HologramFeatureTests.Realtime.Page22 do
  use Hologram.Page

  route "/realtime/22"

  layout HologramFeatureTests.Components.DefaultLayout

  # Sign-in landing page that the logout middleware redirects to.
  def template do
    ~HOLO"""
    <h1>Please sign in</h1>
    """
  end
end
