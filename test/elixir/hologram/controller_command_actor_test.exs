defmodule Hologram.ControllerCommandActorTest do
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.Controller

  alias Hologram.Auth
  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.Entity
  alias Hologram.Realtime.SubscriptionRegistry
  alias Hologram.Realtime.Tombstone
  alias Hologram.Runtime.CSRFProtection
  alias Hologram.Test.Fixtures.Controller.Module33
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Policy.Module1

  @unmasked_csrf_token CSRFProtection.generate_unmasked_token()
  @masked_csrf_token CSRFProtection.get_masked_token(@unmasked_csrf_token)

  @anonymous_session %{
    CSRFProtection.session_key() => @unmasked_csrf_token,
    hologram_session_id: "test-session-id"
  }

  setup do
    wait_for_process_cleanup(SubscriptionRegistry)
    start_supervised!(SubscriptionRegistry)

    wait_for_process_cleanup(Hologram.PubSub)
    start_supervised!({Phoenix.PubSub, name: Hologram.PubSub})

    wait_for_process_cleanup(Tombstone)
    start_supervised!({Tombstone, boot_sync_timeout_ms: 0})

    :ok
  end

  defp binary_to_hex(binary) do
    binary
    |> :binary.bin_to_list()
    |> Enum.map(&Integer.to_string(&1, 16))
    |> Enum.map(&String.downcase/1)
    |> Enum.map_join(&String.pad_leading(&1, 2, "0"))
  end

  defp create_user(email) do
    Module14
    |> Entity.new(email: email)
    |> DB.create!()
  end

  defp entity_count do
    count_sql = ~s|SELECT count(*) FROM "hologram_data"."test_fixtures_policy_module1"|
    {:ok, %{rows: [[count]]}} = Connection.query(count_sql, [])

    count
  end

  defp execute_command(name, params, session) do
    parsed_json =
      name
      |> serialize_payload(params)
      |> Jason.decode!()

    :post
    |> Plug.Test.conn("/hologram/command", "")
    |> Plug.Test.init_test_session(session)
    |> Map.put(:body_params, %{"_json" => parsed_json})
    |> Plug.Conn.put_req_header("x-csrf-token", @masked_csrf_token)
    |> handle_command_request()
  end

  defp grant_count do
    count_sql = ~s|SELECT count(*) FROM "hologram_data"."hologram_role_grant"|
    {:ok, %{rows: [[count]]}} = Connection.query(count_sql, [])

    count
  end

  defp granted_roles(user_id) do
    select_sql =
      ~s|SELECT "role" FROM "hologram_data"."hologram_role_grant" | <>
        ~s|WHERE "user_id" = $1 ORDER BY "role"|

    {:ok, %{rows: rows}} = Connection.query(select_sql, [Codec.encode(user_id, :uuid)])

    Enum.map(rows, fn [role] -> role end)
  end

  defp serialize_payload(name, params) do
    serialized_params =
      Enum.map(params, fn {key, value} ->
        ["a#{key}", "b0#{binary_to_hex(value)}"]
      end)

    serialized_map_data = [
      ["ainstance_id", "b0#{binary_to_hex("test-instance-id")}"],
      ["amodule", "a#{Module33}"],
      ["aname", "a#{name}"],
      ["aparams", %{"t" => "m", "d" => serialized_params}],
      ["asub_receipts", %{"t" => "l", "d" => []}],
      ["atarget", "b0#{binary_to_hex("my_target_1")}"]
    ]

    Jason.encode!([2, %{"t" => "m", "d" => serialized_map_data}])
  end

  defp session_of(user_id) do
    Map.put(@anonymous_session, :hologram_user_id, user_id)
  end

  test "evaluates a plain write in a command handler as the session user's :create" do
    user = create_user("user_0@example.com")

    expected_msg = ~r/^not allowed to create Hologram\.Test\.Fixtures\.Policy\.Module1 "/

    assert_error Hologram.AccessDeniedError, expected_msg, fn ->
      execute_command(
        :my_command_creating_entity_on_the_users_authority,
        %{},
        session_of(user.id)
      )
    end

    assert entity_count() == 0
  end

  test "grants the creator roles of an entity created in a command handler to the session user" do
    user = create_user("user_1@example.com")

    conn = execute_command(:my_command_creating_entity, %{}, session_of(user.id))

    assert conn.status == 200
    assert entity_count() == 1
    assert granted_roles(user.id) == ["maintainer", "owner"]
  end

  test "grants no creator role for an entity created in an anonymous command handler" do
    conn = execute_command(:my_command_creating_entity, %{}, @anonymous_session)

    assert conn.status == 200
    assert entity_count() == 1
    assert grant_count() == 0
  end

  test "raises on an unqualified role grant issued in a command handler" do
    granter = create_user("user_2@example.com")
    user = create_user("user_3@example.com")

    expected_msg = "global roles are granted only by trusted code running without an acting user"

    assert_error Hologram.AccessDeniedError, expected_msg, fn ->
      execute_command(
        :my_command_granting_global_role,
        %{user_id: user.id},
        session_of(granter.id)
      )
    end
  end

  test "raises when a command handler revokes the last role managing a resource" do
    owner = create_user("user_4@example.com")

    resource =
      Module1
      |> Entity.new()
      |> DB.create!()

    Auth.grant_role(owner, resource, :owner)

    expected_msg =
      "cannot revoke the last role managing Hologram.Test.Fixtures.Policy.Module1 " <>
        "#{inspect(resource.id)} - transfer ownership first"

    params = %{resource_id: resource.id, user_id: owner.id}

    assert_error Hologram.AccessDeniedError, expected_msg, fn ->
      execute_command(:my_command_revoking_role, params, session_of(owner.id))
    end
  end
end
