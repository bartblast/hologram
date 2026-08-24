defmodule HologramFeatureTests.WriteClaimsPage do
  use Hologram.Page
  use Hologram.Query

  alias Hologram.AccessDeniedError
  alias HologramFeatureTests.Entities.Note
  alias HologramFeatureTests.Entities.User

  route "/write-claims"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  # No label may be a substring of another - Wallaby matches a button by substring, and this
  # page pairs "Pin note" with "Pin pinned note" on purpose.
  def template do
    ~HOLO"""
    <p>
      <button $click={command: :add_note_as_author}> Add note as author </button>
      <button $click={command: :add_note_as_other}> Add note as other </button>
      <button $click={command: :add_note_by_server}> Add note by server </button>
      <button $click={command: :delete_own_note}> Delete own note </button>
      <button $click={command: :log_in}> Log in </button>
      <button $click={command: :pin_note}> Pin note </button>
      <button $click={command: :pin_pinned_note}> Pin pinned note </button>
      <button $click={command: :update_unrecorded_note}> Update unrecorded note </button>
    </p>
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    """
  end

  def action(:show_result, params, component) do
    put_state(component, :result, params.result)
  end

  def command(:add_note_as_author, _params, server) do
    Note
    |> Entity.new(body: "own", author_id: server.user_id)
    |> DB.create!()

    put_action(server, :show_result, result: "added_note_as_author")
  end

  def command(:add_note_as_other, _params, server) do
    other_user = create_user("other_author@example.com")

    result =
      try do
        Note
        |> Entity.new(body: "other", author_id: other_user.id)
        |> DB.create!()

        "added_note_as_other"
      rescue
        error in AccessDeniedError -> error.message
      end

    put_action(server, :show_result, result: result)
  end

  def command(:add_note_by_server, _params, server) do
    other_user = create_user("server_author@example.com")

    Note
    |> Entity.new(body: "by server", author_id: other_user.id)
    |> trust()
    |> DB.create!()

    put_action(server, :show_result, result: "added_note_by_server")
  end

  def command(:delete_own_note, _params, server) do
    note = create_note(server.user_id, false)

    DB.delete!(note)

    put_action(server, :show_result, result: "deleted_own_note")
  end

  def command(:log_in, _params, server) do
    user = create_user("session@example.com")

    put_action(%{server | user_id: user.id}, :show_result, result: "logged_in")
  end

  def command(:pin_note, _params, server) do
    note = create_note(server.user_id, false)

    note
    |> put_attribute(:pinned, true)
    |> authorize(:pin)
    |> DB.update!()

    put_action(server, :show_result, result: "pinned_note")
  end

  def command(:pin_pinned_note, _params, server) do
    note = create_note(server.user_id, true)

    result =
      try do
        note
        |> put_attribute(:pinned, true)
        |> authorize(:pin)
        |> DB.update!()

        "pinned_pinned_note"
      rescue
        error in AccessDeniedError -> error.message
      end

    put_action(server, :show_result, result: result)
  end

  def command(:update_unrecorded_note, _params, server) do
    note = create_note(server.user_id, false)

    result =
      try do
        DB.update!(%{note | pinned: true})

        "updated_unrecorded_note"
      rescue
        error in ArgumentError -> error.message
      end

    put_action(server, :show_result, result: result)
  end

  # Trusted so the session user becomes the note's owner through the creator role without the
  # :create rule being the thing under test.
  defp create_note(author_id, pinned) do
    Note
    |> Entity.new(author_id: author_id, body: "seeded", pinned: pinned)
    |> trust()
    |> DB.create!()
  end

  defp create_user(email) do
    User
    |> Entity.new(email: email)
    |> trust()
    |> DB.create!()
  end
end
