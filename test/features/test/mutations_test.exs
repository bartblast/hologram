defmodule HologramFeatureTests.MutationsTest do
  # async: false - each test truncates the shared tables.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.Entity
  alias Hologram.Entity.Model
  alias HologramFeatureTests.Entities.Note
  alias HologramFeatureTests.Entities.User
  alias HologramFeatureTests.MutationsPage

  # All three tables truncate in one statement: the role grant table's foreign keys to the user
  # table make Postgres reject truncating the referenced table alone.
  setup do
    await_evaluator_drain()

    tables =
      Enum.map_join([Note, RoleGrant, User], ", ", fn entity_type ->
        ~s("hologram_data"."#{Mapper.table_name(entity_type)}")
      end)

    {:ok, _result} = Connection.query("TRUNCATE #{tables}", [])

    :ok
  end

  # Polls for the answer the posted batch left behind, and clears it so a second post in the same
  # test cannot read the first one's.
  defp await_response(session) do
    Enum.reduce_while(1..100, nil, fn _attempt, _acc ->
      case script_result(session, "return globalThis.__mutationResponse;") do
        nil ->
          Process.sleep(50)
          {:cont, nil}

        response ->
          execute_script(session, "globalThis.__mutationResponse = null;")
          {:halt, response}
      end
    end)
  end

  defp create_note_write(author_id, body) do
    %{
      "op" => "create",
      "type" => inspect(Note),
      "id" => Entity.generate_id(),
      "data" => %{"body" => body, "author_id" => author_id},
      "claim" => nil,
      "stamp" => System.os_time(:millisecond) * 1024
    }
  end

  defp log_in(session) do
    session
    |> visit(MutationsPage)
    |> click(button("Log in"))
    |> assert_text(css("#result"), "logged_in")
  end

  # Proves the DOM changed without the page being fetched again - a reload would take this marker
  # with it, so a passing assertion after one would say nothing.
  defp mark_this_page_load(session) do
    execute_script(session, "globalThis.__thisPageLoad = 'held';")
  end

  defp assert_same_page_load(session) do
    assert_script_result(session, "return globalThis.__thisPageLoad;", "held")
  end

  # The batch is built and sent IN THE BROWSER, from the identity and the model hash the runtime
  # already holds - so what this exercises is the endpoint a client will really reach, headers
  # included, rather than a request assembled in the test process.
  defp post_batch(session, seq, writes) do
    script = """
    const payload = {
      instance_id: globalThis.Hologram.instanceId,
      client_id: globalThis.Hologram.instanceId,
      seq: #{seq},
      model_hash: globalThis.Hologram.sync.modelHash,
      writes: #{Jason.encode!(writes)}
    };

    fetch("/hologram/mutation", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Csrf-Token": globalThis.Hologram.csrfToken
      },
      body: JSON.stringify(payload)
    })
      .then((response) => response.json())
      .then((json) => { globalThis.__mutationResponse = json; });
    """

    execute_script(session, script)
  end

  defp session_user do
    User
    |> DB.read()
    |> Enum.find(&(&1.email == "session@example.com"))
  end

  feature "applies a batch posted from the page and shows its row through the stream, not a reload",
          %{session: session} do
    session = log_in(session)

    mark_this_page_load(session)

    post_batch(session, 1, [create_note_write(session_user().id, "posted")])

    assert await_response(session) == %{"status" => "confirmed", "dropped" => %{}}

    session
    |> assert_text(css("#notes"), "posted")
    |> assert_same_page_load()

    assert [%Note{body: "posted"}] = DB.read(Note)
  end

  feature "refuses a batch the acting user's policies deny", %{session: session} do
    session = log_in(session)

    other_author =
      User
      |> Entity.new(email: "other@example.com")
      |> DB.create!()

    post_batch(session, 1, [create_note_write(other_author.id, "denied")])

    response = await_response(session)

    assert response["status"] == "rejected"
    assert response["write"] == 0
    assert response["reason"] =~ "not allowed to create"

    assert DB.read(Note) == []
  end

  feature "applies a batch that arrives twice once", %{session: session} do
    session = log_in(session)

    writes = [create_note_write(session_user().id, "once")]

    post_batch(session, 1, writes)
    first_response = await_response(session)

    post_batch(session, 1, writes)
    second_response = await_response(session)

    assert first_response == %{"status" => "confirmed", "dropped" => %{}}
    assert second_response == first_response

    assert [%Note{body: "once"}] = DB.read(Note)
  end

  feature "refuses a batch built against another model", %{session: session} do
    session = log_in(session)

    script = """
    globalThis.Hologram.sync.modelHash = "not-this-build";
    """

    execute_script(session, script)

    post_batch(session, 1, [create_note_write(session_user().id, "stale")])

    response = await_response(session)

    assert response["status"] == "rejected"
    assert response["write"] == nil
    assert response["reason"] == ~s[Type.atom("stale_build")]

    assert DB.read(Note) == []
    assert Model.hash() != "not-this-build"
  end
end
