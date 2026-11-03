defmodule HologramFeatureTests.SessionRestore.ProtectedPage do
  use Hologram.Page

  alias Hologram.UI.Link
  alias HologramFeatureTests.SessionRestore.LoginPage

  route "/session-restore/protected"

  layout HologramFeatureTests.Components.DefaultLayout

  middleware :require_login

  def require_login(%{user_id: nil} = server, _opts) do
    put_redirect(server, LoginPage)
  end

  def require_login(server, _opts), do: server

  def init(_params, component, server) do
    put_state(component, marker: "none", user: server.user_id)
  end

  def template do
    ~HOLO"""
    <h1>Session Restore / Protected Page</h1>
    <p>User: <strong id="user">{@user}</strong></p>
    <p>Marker: <strong id="marker">{@marker}</strong></p>
    <p>
      <button $click="put_marker">Put marker</button>
      <Link to={LoginPage}>Login page link</Link>
    </p>
    """
  end

  def action(:put_marker, _params, component) do
    put_state(component, :marker, "set")
  end
end
