defmodule HologramFeatureTests.OptimisticGrantsPage do
  use Hologram.Page
  use Hologram.DB

  alias Hologram.Auth
  alias HologramFeatureTests.Components.OptimisticGrants.GrantList
  alias HologramFeatureTests.Entities.Document
  alias HologramFeatureTests.Entities.Note
  alias HologramFeatureTests.Entities.User

  route "/optimistic-grants"

  layout HologramFeatureTests.Components.DefaultLayout

  # The document and the other user are seeded by the test before the visit, and read here as
  # trusted code so the page holds their ids whoever is signed in. The session user's id is
  # what the page was mounted under - a reload after "Log in" is what makes it theirs.
  def init(_params, component, server) do
    [document] =
      Document
      |> filter(title: "shared_document")
      |> trust()
      |> DB.read()

    [other_user] =
      User
      |> filter(email: "other@example.com")
      |> trust()
      |> DB.read()

    component
    |> put_state(:document, document)
    |> put_state(:other_user_id, other_user.id)
    |> put_state(:result, nil)
    |> put_state(:session_user_id, server.user_id)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="create_and_share"> Create and share </button>
      <button $click="grant_editor"> Grant editor </button>
      <button $click="grant_owner"> Grant owner </button>
      <button $click="leave"> Leave </button>
      <button $click={command: :log_in}> Log in </button>
      <button $click="revoke_editor"> Revoke editor </button>
    </p>
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    <GrantList cid="grant_list" />
    """
  end

  # Every verb runs in the browser: the row appears or disappears at once, the write joins the
  # action's batch, and the server replays the gate when it lands. A refusal the browser can make
  # itself is raised here; one only the server can make comes back as a rejected batch.
  #
  # The first of them needs the roles a row hands its creator: the note is made and shared in one
  # action, so the grant is judged against a row this browser made a line earlier and has been
  # told nothing about yet.
  def action(:create_and_share, _params, component) do
    {:ok, note} =
      %{author_id: component.state.session_user_id, body: "shared_note"}
      |> Note.new()
      |> DB.create()

    grant(component, :create_and_share, component.state.other_user_id, :editor, note)
  end

  def action(:grant_editor, _params, component) do
    grant(component, :grant_editor, component.state.other_user_id, :editor)
  end

  def action(:grant_owner, _params, component) do
    grant(component, :grant_owner, component.state.other_user_id, :owner)
  end

  def action(:leave, _params, component) do
    revoke(component, :leave, component.state.session_user_id, :editor)
  end

  def action(:revoke_editor, _params, component) do
    revoke(component, :revoke_editor, component.state.other_user_id, :editor)
  end

  def action(:show_result, params, component) do
    put_state(component, :result, params.result)
  end

  def command(:log_in, _params, server) do
    user =
      %{email: "session@example.com"}
      |> User.new()
      |> trust()
      |> DB.create!()

    put_action(%{server | user_id: user.id}, :show_result, result: "logged_in")
  end

  defp grant(component, name, user_id, role) do
    grant(component, name, user_id, role, component.state.document)
  end

  defp grant(component, name, user_id, role, resource) do
    result =
      try do
        Auth.grant_role(user_id, resource, role)
        "#{name}_ok"
      rescue
        Hologram.AccessDeniedError -> "#{name}_refused"
      end

    put_state(component, :result, result)
  end

  defp revoke(component, name, user_id, role) do
    result =
      try do
        Auth.revoke_role(user_id, component.state.document, role)
        "#{name}_ok"
      rescue
        Hologram.AccessDeniedError -> "#{name}_refused"
      end

    put_state(component, :result, result)
  end
end
