defmodule HologramFeatureTests.ForeignSessionPage do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Entities.GuestEntry

  route "/foreign-session"

  layout HologramFeatureTests.Components.DefaultLayout

  state :result, :string

  def init(_params, component, _server) do
    put_state(component, :result, "none")
  end

  # An app signing its users in with ids of its own, like the serial ids an Ecto table gives them,
  # rather than a user entity's - the data layer reads such a session as a visitor.
  def template do
    ~HOLO"""
    <p>
      <button $click={command: :sign_in}> Sign in with an app id </button>
      <button $click={action: :write_in_browser}> Write in the browser </button>
      <button $click={command: :write_on_server}> Write on the server </button>
    </p>
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    """
  end

  def action(:show_result, params, component) do
    put_state(component, :result, params.result)
  end

  def action(:write_in_browser, _params, component) do
    {:ok, _entry} =
      %{text: "browser"}
      |> GuestEntry.new()
      |> DB.create()

    put_state(component, :result, "written_in_browser")
  end

  def command(:sign_in, _params, server) do
    server
    |> put_user_id(7)
    |> put_action(:show_result, result: "signed_in")
  end

  def command(:write_on_server, _params, server) do
    {:ok, _entry} =
      %{text: "server"}
      |> GuestEntry.new()
      |> DB.create()

    put_action(server, :show_result, result: "written_on_server")
  end
end
