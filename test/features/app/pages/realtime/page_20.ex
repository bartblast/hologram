defmodule HologramFeatureTests.Realtime.Page20 do
  use Hologram.Page

  alias HologramFeatureTests.Realtime.Page22

  route "/realtime/20"

  layout HologramFeatureTests.Components.DefaultLayout

  middleware :log_out

  # Logs the user out (server.user_id -> nil) and redirects in the same step. The
  # terminal (redirect) path must still announce the identity change so live SSE
  # connections on the session drop their user-authorized bindings.
  def log_out(server, _opts) do
    server
    |> Map.put(:user_id, nil)
    |> put_redirect(Page22)
  end

  def template do
    ~HOLO"""
    <h1>Realtime / Page 20</h1>
    """
  end
end
