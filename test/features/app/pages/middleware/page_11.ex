defmodule HologramFeatureTests.Middleware.Page11 do
  use Hologram.Page

  route "/middleware/11"

  layout HologramFeatureTests.Components.DefaultLayout

  # Redirects somewhere no page owns. The framework serves /hologram/ping itself, so this exercises
  # the target-outside-the-app case without depending on a host the tests cannot reach.
  middleware :redirect

  def redirect(server, _opts) do
    put_redirect(server, "/hologram/ping")
  end

  def template do
    ~HOLO"""
    <h1>Middleware / Page 11</h1>
    """
  end
end
