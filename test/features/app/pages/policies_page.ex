defmodule HologramFeatureTests.PoliciesPage do
  use Hologram.Page
  use Hologram.DB

  alias Hologram.Auth
  alias HologramFeatureTests.Components.Policies.Component1
  alias HologramFeatureTests.Entities.Document
  alias HologramFeatureTests.Entities.User

  route "/policies"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click={command: :create_own_document}> Create own document </button>
      <button $click={command: :grant_editor}> Grant editor </button>
      <button $click={command: :grant_owner_as_editor}> Grant owner as editor </button>
      <button $click={command: :leave_last_owner}> Leave last owner </button>
      <button $click={command: :log_in}> Log in </button>
      <button $click={command: :read_documents_as_server}> Read documents as server </button>
      <button $click={command: :read_documents_as_user}> Read documents as user </button>
      <button $click={command: :revoke_editor}> Revoke editor </button>
      <button $click={command: :seed_documents}> Seed documents </button>
    </p>
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    <Component1 cid="component_1" />
    """
  end

  def action(:show_result, params, component) do
    put_state(component, :result, params.result)
  end

  def command(:create_own_document, _params, server) do
    %{title: "own_document"}
    |> Document.new()
    |> trust()
    |> DB.create!()

    put_action(server, :show_result, result: "created_own_document")
  end

  def command(:grant_editor, _params, server) do
    document = create_document("granted_document")
    other_user = create_user("granted@example.com")

    Auth.grant_role(other_user, document, :editor)

    put_action(server, :show_result, result: "grant_editor_#{can?(other_user, :read, document)}")
  end

  # The session user is an editor of a document somebody else made - seeded by the test, since a
  # document created here would make them its owner.
  def command(:grant_owner_as_editor, _params, server) do
    [document] =
      Document
      |> filter(title: "escalation_document")
      |> trust()
      |> DB.read()

    other_user = create_user("escalated@example.com")

    result =
      try do
        Auth.grant_role(other_user, document, :owner)
        "grant_owner_as_editor_granted"
      rescue
        Hologram.AccessDeniedError -> "grant_owner_as_editor_refused"
      end

    put_action(server, :show_result, result: result)
  end

  def command(:leave_last_owner, _params, server) do
    document = create_document("last_owner_document")

    result =
      try do
        Auth.revoke_role(server.user_id, document, :owner)
        "left_document"
      rescue
        error in Hologram.AccessDeniedError -> error.message
      end

    put_action(server, :show_result, result: result)
  end

  def command(:log_in, _params, server) do
    user = create_user("session@example.com")

    put_action(%{server | user_id: user.id}, :show_result, result: "logged_in")
  end

  def command(:read_documents_as_server, _params, server) do
    titles =
      Document
      |> order_by(:title)
      |> trust()
      |> DB.read()
      |> Enum.map_join(",", & &1.title)

    put_action(server, :show_result, result: "read_as_server_#{titles}")
  end

  def command(:read_documents_as_user, _params, server) do
    titles =
      Document
      |> order_by(:title)
      |> DB.read()
      |> Enum.map_join(",", & &1.title)

    put_action(server, :show_result, result: "read_as_user_#{titles}")
  end

  def command(:revoke_editor, _params, server) do
    document = create_document("revoked_document")
    other_user = create_user("revoked@example.com")

    Auth.grant_role(other_user, document, :editor)
    Auth.revoke_role(other_user, document, :editor)

    put_action(server, :show_result, result: "revoke_editor_#{can?(other_user, :read, document)}")
  end

  def command(:seed_documents, _params, server) do
    %{public: true, title: "public_document"}
    |> Document.new()
    |> trust()
    |> DB.create!()

    create_document("private_document")

    put_action(server, :show_result, result: "seeded_documents")
  end

  defp create_document(title) do
    %{title: title}
    |> Document.new()
    |> trust()
    |> DB.create!()
  end

  defp create_user(email) do
    %{email: email}
    |> User.new()
    |> trust()
    |> DB.create!()
  end
end
