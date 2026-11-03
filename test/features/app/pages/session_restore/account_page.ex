defmodule HologramFeatureTests.SessionRestore.AccountPage do
  use Hologram.Page

  alias Hologram.UI.Link
  alias HologramFeatureTests.SessionRestore.LoginPage

  route "/session-restore/account"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, server) do
    put_state(component, marker: "none", user: server.user_id || "anonymous")
  end

  # The marker is state only the page holds: Back shows it only by restoring the page as it was
  # left.
  def template do
    ~HOLO"""
    <h1>Session Restore / Account Page</h1>
    <p>User: <strong id="user">{@user}</strong></p>
    <p>Marker: <strong id="marker">{@marker}</strong></p>
    <p>
      <button $click="put_marker">Put marker</button>
      <Link to={LoginPage}>Login page link</Link>
      <a href="#bottom">Bottom link</a>
    </p>
    <p id="bottom">Bottom</p>
    """
  end

  def action(:put_marker, _params, component) do
    put_state(component, :marker, "set")
  end
end
