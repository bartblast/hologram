defmodule HologramFeatureTests.PermissionCatchupTest do
  # async: false - each test truncates the shared tables.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.Auth
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.Entities.Document
  alias HologramFeatureTests.Entities.Note
  alias HologramFeatureTests.Entities.User
  alias HologramFeatureTests.Policies.Page1

  # The resume end of the permission check. `permission_checks_test.exs` holds the LIVE halves of
  # these two - a grant written while the stream is attached, delivered by the round it wakes -
  # and these assert the same outcome for a change that lands while no stream is attached at all.
  #
  # The lever is `simulate_sse_disconnect/1` plus the client's own reconnect: with the stream
  # killed, a grant written from the test process wakes nothing this browser can hear, so what
  # reaches the screen afterwards can only have come through the resume. The gap the client comes
  # back with names the grant row and nothing else - the documents it covers never moved - so
  # before this issue neither of these could pass.
  setup do
    await_evaluator_drain()

    tables =
      Enum.map_join([Document, Note, RoleGrant, User], ", ", fn entity_type ->
        ~s("hologram_data"."#{Mapper.table_name(entity_type)}")
      end)

    {:ok, _result} = Connection.query("TRUNCATE #{tables}", [])

    :ok
  end

  # Proves the DOM changed without the page being fetched again - a reload would take this
  # marker with it, so a passing assertion after one would say nothing.
  defp mark_this_page_load(session) do
    execute_script(session, "globalThis.__thisPageLoad = 'held';")
  end

  defp assert_same_page_load(session) do
    assert_script_result(session, "return globalThis.__thisPageLoad;", "held")
  end

  defp create_document(title) do
    %{public: true, title: title}
    |> Document.new()
    |> DB.create!()
  end

  defp session_user do
    User
    |> DB.read()
    |> Enum.find(&(&1.email == "manager@example.com"))
  end

  feature "hands over what a grant given while away covers", %{session: session} do
    document = create_document("almanac")

    session
    |> visit(Page1)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")
    |> reload()
    |> assert_text(css("#managed_documents"), ~r/^$/)
    |> mark_this_page_load()

    instance_id = current_instance_id(session)
    :ok = simulate_sse_disconnect(instance_id)

    Auth.grant_role(session_user(), document, :owner)

    # Wallaby's own retry rides out the reconnect backoff, which starts at 250 ms.
    session
    |> assert_text(css("#managed_documents"), ~r/^almanac$/)
    |> assert_same_page_load()
  end

  feature "takes away what a revoked grant covered", %{session: session} do
    document = create_document("bestiary")

    session
    |> visit(Page1)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")

    user = session_user()
    Auth.grant_role(user, document, :owner)

    session
    |> reload()
    |> assert_text(css("#managed_documents"), ~r/^bestiary$/)
    |> mark_this_page_load()

    instance_id = current_instance_id(session)
    :ok = simulate_sse_disconnect(instance_id)

    Auth.revoke_role(user, document, :owner)

    session
    |> assert_text(css("#managed_documents"), ~r/^$/)
    |> assert_same_page_load()
  end
end
