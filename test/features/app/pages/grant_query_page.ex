defmodule HologramFeatureTests.GrantQueryPage do
  use Hologram.Page
  use Hologram.DB

  alias Hologram.Auth
  alias HologramFeatureTests.Components.GrantQuery.GrantsOnDocument
  alias HologramFeatureTests.Entities.Document
  alias HologramFeatureTests.Entities.User

  route "/grant-query"

  layout HologramFeatureTests.Components.DefaultLayout

  # The document and the third user are seeded by the test before the visit, and read here as
  # trusted code so the page holds their ids whoever is signed in.
  def init(_params, component, server) do
    [document] =
      Document
      |> filter(title: "queried_document")
      |> trust()
      |> DB.read()

    [third_user] =
      User
      |> filter(email: "third@example.com")
      |> trust()
      |> DB.read()

    component
    |> put_state(:document, document)
    |> put_state(:result, nil)
    |> put_state(:session_user_id, server.user_id)
    |> put_state(:third_user_id, third_user.id)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click={command: :log_in}> Log in </button>
      <button $click="share"> Share with the third user </button>
    </p>
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    <GrantsOnDocument cid="grants" document_id={@document.id} />
    """
  end

  # The grant runs in the browser and joins the action's batch, so the row it makes is in the
  # client's own database before anything is sent - and the list above, which queries that
  # database by entity_type, has to find it under the label the browser wrote.
  def action(:share, _params, component) do
    result =
      try do
        Auth.grant_role(component.state.third_user_id, component.state.document, :editor)
        "share_ok"
      rescue
        Hologram.AccessDeniedError -> "share_refused"
      end

    put_state(component, :result, result)
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
end
