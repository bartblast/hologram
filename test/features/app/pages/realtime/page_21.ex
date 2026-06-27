defmodule HologramFeatureTests.Realtime.Page21 do
  use Hologram.Page

  alias HologramFeatureTests.Realtime.Page23

  route "/realtime/21"

  layout HologramFeatureTests.Components.DefaultLayout

  middleware :reauthenticate

  # Re-authenticates as user 2 (server.user_id 1 -> 2) and redirects in the same
  # step. The terminal (redirect) path must still announce the identity change so
  # live SSE connections on the session move to the new user.
  def reauthenticate(server, _opts) do
    server
    |> Map.put(:user_id, 2)
    |> put_redirect(Page23)
  end

  def template do
    ~HOLO"""
    <h1>Realtime / Page 21</h1>
    """
  end
end
