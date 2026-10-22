defmodule HologramFeatureTests.Policies.Page4 do
  use Hologram.Page
  use Hologram.DB

  alias Hologram.Auth
  alias HologramFeatureTests.Components.Policies.Component5
  alias HologramFeatureTests.Entities.Document
  alias HologramFeatureTests.Entities.User

  route "/policies/4"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, server) do
    component
    |> put_state(:result, "none")
    |> put_state(:session_user_id, server.user_id)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="leave"> Leave </button>
      <button $click={command: :log_in}> Log in </button>
    </p>
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    <Component5 cid="component_5" />
    """
  end

  # Runs in the browser over local rows: the document is read from the local database and the
  # session user's own editor role on it is revoked - the one revocation needing no permission -
  # so the role check on the render that follows answers from the browser's own rows, before the
  # write lands.
  def action(:leave, _params, component) do
    [document] =
      Document
      |> filter(title: "ledger")
      |> DB.read()

    Auth.revoke_role(component.state.session_user_id, :editor, document)

    put_state(component, :result, "left")
  end

  def action(:show_result, params, component) do
    put_state(component, :result, params.result)
  end

  def command(:log_in, _params, server) do
    user =
      %{email: "member@example.com"}
      |> User.new()
      |> DB.create!()

    put_action(%{server | user_id: user.id}, :show_result, result: "logged_in")
  end
end
