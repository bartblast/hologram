defmodule HologramFeatureTests.SessionRestore.LoginPage do
  use Hologram.Page

  alias Hologram.UI.Link
  alias HologramFeatureTests.SessionRestore.AccountPage
  alias HologramFeatureTests.SessionRestore.ProtectedPage

  route "/session-restore/login"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, "none")
  end

  def template do
    ~HOLO"""
    <h1>Session Restore / Login Page</h1>
    <p>
      <button $click={command: :log_in, params: %{user_id: "alice"}}>Log in as Alice</button>
      <button $click={command: :log_in, params: %{user_id: "bob"}}>Log in as Bob</button>
      <button $click={command: :log_out}>Log out</button>
      <button $click={command: :put_cart_item}>Put cart item</button>
    </p>
    <p>
      <Link to={AccountPage}>Account page link</Link>
      <Link to={ProtectedPage}>Protected page link</Link>
    </p>
    <p>Result: <strong id="result">{@result}</strong></p>
    """
  end

  def action(:show_result, params, component) do
    put_state(component, :result, params.result)
  end

  def command(:log_in, params, server) do
    server
    |> put_user_id(params.user_id)
    |> put_action(:show_result, result: "logged in as #{params.user_id}")
  end

  def command(:log_out, _params, server) do
    server
    |> delete_user_id()
    |> put_action(:show_result, result: "logged out")
  end

  # A session write that leaves the identity alone.
  def command(:put_cart_item, _params, server) do
    server
    |> put_session(:cart, ["book"])
    |> put_action(:show_result, result: "cart updated")
  end
end
