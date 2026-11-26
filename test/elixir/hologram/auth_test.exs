defmodule Hologram.AuthTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Auth

  alias Hologram.Auth.Context
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations
  alias Hologram.DB.Oplog
  alias Hologram.DB.SetLock
  alias Hologram.Entity
  alias Hologram.MisuseError
  alias Hologram.Policy
  alias Hologram.Policy.Evaluator
  alias Hologram.Query
  alias Hologram.Sync.Carry
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module26, as: Channel
  alias Hologram.Test.Fixtures.Entity.Module28, as: Message
  alias Hologram.Test.Fixtures.Entity.Module29, as: Label
  alias Hologram.Test.Fixtures.Entity.Module32, as: CountedChannel
  alias Hologram.Test.Fixtures.Entity.Module33, as: CountedMessage
  alias Hologram.Test.Fixtures.Policy.Module1
  alias Hologram.Test.Fixtures.Policy.Module10
  alias Hologram.Test.Fixtures.Policy.Module11
  alias Hologram.Test.Fixtures.Policy.Module12
  alias Hologram.Test.Fixtures.Policy.Module17, as: PolicyProject
  alias Hologram.Test.Fixtures.Policy.Module18, as: PolicyMember
  alias Hologram.Test.Fixtures.Policy.Module19, as: PolicyLabel
  alias Hologram.Test.Fixtures.Policy.Module2
  alias Hologram.Test.Fixtures.Policy.Module20, as: PolicyTask
  alias Hologram.Test.Fixtures.Policy.Module21, as: PolicyTag
  alias Hologram.Test.Fixtures.Policy.Module22, as: PolicyBoard
  alias Hologram.Test.Fixtures.Policy.Module23, as: PolicyCard
  alias Hologram.Test.Fixtures.Policy.Module24, as: PolicyShelf
  alias Hologram.Test.Fixtures.Policy.Module25, as: PolicyProfile
  alias Hologram.Test.Fixtures.Policy.Module36
  alias Hologram.Test.Fixtures.Policy.Module37
  alias Hologram.Test.Fixtures.Policy.Module38
  alias Hologram.Test.Fixtures.Policy.Module39
  alias Hologram.Test.Fixtures.Policy.Module4
  alias Hologram.Test.Fixtures.Policy.Module46
  alias Hologram.Test.Fixtures.Policy.Module47
  alias Hologram.Test.Fixtures.Policy.Module48
  alias Hologram.Test.Fixtures.Policy.Module49
  alias Hologram.Test.Fixtures.Policy.Module5
  alias Hologram.Test.Fixtures.Policy.Module58, as: ChangedProject
  alias Hologram.Test.Fixtures.Policy.Module59, as: ChangedTask
  alias Hologram.Test.Fixtures.Policy.Module8
  alias Hologram.Test.Fixtures.Policy.Module9, as: SelfParent
  alias Hologram.Test.Fixtures.Policy.Readers.Module20, as: ReadersModule20
  alias Hologram.Test.Fixtures.Policy.Readers.Module21, as: ReadersModule21
  alias Hologram.Test.Fixtures.Policy.Readers.Module25, as: ReadersModule25
  alias Hologram.Test.Fixtures.Policy.Readers.Module28, as: ReadersModule28
  alias Hologram.Test.Fixtures.Policy.Readers.Module5, as: ReadersModule5
  alias Hologram.Test.Fixtures.Role

  # Built at runtime, so the compiler's type checker doesn't flag a deliberately bad option list.
  defp computed_opts(opts) do
    Enum.map(opts, & &1)
  end

  defp create_user(email) do
    %{email: email}
    |> Module14.new()
    |> DB.create!()
  end

  defp create_parent(public \\ false) do
    %{public: public}
    |> Module2.new()
    |> DB.create!()
  end

  # A Module5 row whose parent is a Module1 row with the given parent - the row two hops away from
  # a Module12 row pointing at the Module5 row is the Module1 row.
  defp create_path_rows(parent_id) do
    resource =
      %{parent_id: parent_id}
      |> Module1.new()
      |> DB.create!()

    middle =
      %{parent_id: resource.id}
      |> Module5.new()
      |> DB.create!()

    {resource, middle}
  end

  defp create_resource do
    DB.create!(Module1.new())
  end

  defp grant_id(user_id) do
    select_sql = ~s|SELECT "id" FROM "hologram_data"."hologram_role_grant" WHERE "user_id" = $1|

    {:ok, %{rows: [[id]]}} = Connection.query(select_sql, [Codec.encode(user_id, :id)])

    Codec.decode(id, :id)
  end

  defp grant_rows(user_id) do
    select_sql =
      ~s|SELECT "entity_type", "entity_id", "role", "granted_by_id", "created_at" | <>
        ~s|FROM "hologram_data"."hologram_role_grant" WHERE "user_id" = $1|

    {:ok, %{rows: rows}} = Connection.query(select_sql, [Codec.encode(user_id, :id)])

    Enum.map(rows, fn [entity_type, entity_id, role, granted_by_id, created_at] ->
      %{
        created_at: created_at,
        granted_by_id: granted_by_id && Codec.decode(granted_by_id, :id),
        entity_id: entity_id && Codec.decode(entity_id, :id),
        entity_type: entity_type,
        role: role
      }
    end)
  end

  # The row a batch's grant write arrives as - what Hologram.Mutation.Write.to_entity/1 hands the
  # applier, with the granter already taken from the acting user.
  defp grant_struct(opts) do
    entity_id = Keyword.get(opts, :entity_id)
    entity_type = Keyword.get(opts, :entity_type)
    role = Keyword.fetch!(opts, :role)
    user_id = Keyword.fetch!(opts, :user_id)

    %RoleGrant{
      entity_id: entity_id,
      entity_type: entity_type,
      granted_by_id: Keyword.get(opts, :granted_by_id),
      id: RoleGrant.derive_id(user_id, entity_type, entity_id, role),
      role: role,
      user_id: user_id
    }
  end

  defp revocation_effects do
    select_sql = """
    SELECT "type", "entity_id"
    FROM "hologram_system"."oplog"
    WHERE "op" = 'del_entity'
    ORDER BY "seq"
    """

    {:ok, %{rows: rows}} = Connection.query(select_sql)

    Enum.map(rows, fn [type, entity_id] -> {type, Codec.decode(entity_id, :id)} end)
  end

  # The row apply_revocation_write/2 is handed - read back from the store by id, the way the applier
  # reads it, rather than built: a revocation is judged against the grant as it was made. Read raw,
  # because the store's own read policy would withhold it from a test running with no actor.
  defp held_grant(user_id) do
    EntityOperations.get(RoleGrant, grant_id(user_id))
  end

  describe "as_current_user/1" do
    # Runs the function in a Task on the test's sandboxed connection.
    defp in_sandboxed_task(fun) do
      test_pid = self()

      fn ->
        :ok = DBConnection.Ownership.ownership_allow(DB.pool_name(), test_pid, self(), [])
        Connection.enter_sandbox()

        fun.()
      end
      |> Task.async()
      |> Task.await()
    end

    test "gives the work the user's access in another process" do
      user = create_user("user_as_current_1@example.com")

      private_row =
        %{public: false}
        |> Module1.new()
        |> DB.create!()

      public_row =
        %{public: true}
        |> Module1.new()
        |> DB.create!()

      fun =
        Context.with_actor(user.id, fn ->
          as_current_user(fn ->
            {DB.read(Module1, private_row.id), DB.read(Module1, public_row.id).id}
          end)
        end)

      assert in_sandboxed_task(fun) == {nil, public_row.id}
    end

    test "refuses the work a write the user's rules refuse" do
      user = create_user("user_as_current_2@example.com")

      row =
        %{priority: 5, public: true}
        |> Module1.new()
        |> DB.create!()

      fun =
        Context.with_actor(user.id, fn ->
          as_current_user(fn ->
            row
            |> Hologram.Query.put_attribute(:priority, 7)
            |> DB.update()
          end)
        end)

      result =
        in_sandboxed_task(fn ->
          try do
            fun.()
          rescue
            Hologram.AccessDeniedError -> :denied
          end
        end)

      assert result == :denied
      assert DB.read(Module1, row.id).priority == 5
    end

    test "lets the work write what the user's rules allow" do
      user = create_user("user_as_current_3@example.com")

      row =
        %{author_id: user.id, public: true}
        |> Module1.new()
        |> DB.create!()

      other_user = create_user("user_as_current_4@example.com")

      fun =
        Context.with_actor(user.id, fn ->
          as_current_user(fn ->
            row
            |> Hologram.Query.put_attribute(:author_id, other_user.id)
            |> DB.update()
          end)
        end)

      assert in_sandboxed_task(fun) == :ok
      assert DB.read(Module1, row.id).author_id == other_user.id
    end
  end

  # The gates are spread over the read path, the writer and the role verbs, so each is pinned.
  describe "work a session moved to another process" do
    # Runs the function in a Task the session started, answering :refused for the refusal.
    defp in_session_task(user_id, fun) do
      Context.with_actor(user_id, fn ->
        in_sandboxed_task(fn ->
          try do
            {:ran, fun.()}
          rescue
            error in MisuseError ->
              assert error.message =~ "started for a request's work"

              :refused
          end
        end)
      end)
    end

    defp create_private_row do
      %{priority: 5, public: false}
      |> Module1.new()
      |> DB.create!()
    end

    test "is refused a read by id" do
      user = create_user("user_moved_1@example.com")
      row = create_private_row()

      assert in_session_task(user.id, fn -> DB.read(Module1, row.id) end) == :refused
    end

    test "is refused a read by query" do
      user = create_user("user_moved_2@example.com")

      assert in_session_task(user.id, fn -> DB.read(Module1) end) == :refused
    end

    test "is refused in a signed-out visitor's session" do
      row = create_private_row()

      assert in_session_task(nil, fn -> DB.read(Module1, row.id) end) == :refused
    end

    test "is refused a create" do
      user = create_user("user_moved_3@example.com")

      entity = Module1.new()

      assert in_session_task(user.id, fn -> DB.create(entity) end) == :refused
    end

    test "is refused an update of a struct" do
      user = create_user("user_moved_4@example.com")
      row = create_private_row()
      changed = Hologram.Query.put_attribute(row, :priority, 7)

      assert in_session_task(user.id, fn -> DB.update(changed) end) == :refused
      assert DB.read(Module1, row.id).priority == 5
    end

    test "is refused an update by type and id" do
      user = create_user("user_moved_5@example.com")
      row = create_private_row()

      assert in_session_task(user.id, fn -> DB.update(Module1, row.id, priority: 7) end) ==
               :refused

      assert DB.read(Module1, row.id).priority == 5
    end

    test "is refused a delete of a struct" do
      user = create_user("user_moved_6@example.com")
      row = create_private_row()

      assert in_session_task(user.id, fn -> DB.delete(row) end) == :refused
      assert DB.read(Module1, row.id)
    end

    test "is refused a delete by type and id" do
      user = create_user("user_moved_7@example.com")
      row = create_private_row()

      assert in_session_task(user.id, fn -> DB.delete(Module1, row.id) end) == :refused
      assert DB.read(Module1, row.id)
    end

    test "is refused a role grant" do
      user = create_user("user_moved_8@example.com")
      row = create_private_row()

      assert in_session_task(user.id, fn -> grant_role(user, :viewer, row) end) == :refused
      refute has_role?(user, :viewer, row)
    end

    test "is refused a role revocation" do
      user = create_user("user_moved_9@example.com")
      row = create_private_row()
      grant_role(user, :viewer, row)

      assert in_session_task(user.id, fn -> revoke_role(user, :viewer, row) end) == :refused
      assert has_role?(user, :viewer, row)
    end

    test "is refused a job" do
      user = create_user("user_moved_10@example.com")

      assert in_session_task(user.id, fn ->
               Hologram.Job.create(Hologram.Test.Fixtures.Job.Module1)
             end) == :refused
    end

    test "is refused the user's id, which would read as a signed-out visitor" do
      user = create_user("user_moved_11@example.com")

      assert in_session_task(user.id, fn -> user_id() end) == :refused
    end

    test "reads past the rules with a trust claim" do
      user = create_user("user_moved_12@example.com")
      row = create_private_row()

      {:ran, rows} =
        in_session_task(user.id, fn ->
          Module1
          |> Hologram.Query.trust()
          |> DB.read()
        end)

      assert Enum.map(rows, & &1.id) == [row.id]
    end

    test "writes past the rules with a trust claim" do
      user = create_user("user_moved_13@example.com")
      row = create_private_row()

      changed =
        row
        |> Hologram.Query.put_attribute(:priority, 7)
        |> Hologram.Query.trust()

      assert {:ran, :ok} = in_session_task(user.id, fn -> DB.update(changed) end)
      assert DB.read(Module1, row.id).priority == 7
    end

    test "grants a role with a trust claim" do
      user = create_user("user_moved_14@example.com")
      row = create_private_row()

      assert {:ran, _grant} =
               in_session_task(user.id, fn -> grant_role(user, :viewer, row, trust: true) end)

      assert has_role?(user, :viewer, row)
    end

    # The trust claim is the server's authority: the job doesn't run as the session's user.
    test "creates a job that runs as the server with a trust claim" do
      user = create_user("user_moved_15@example.com")

      assert {:ran, {:ok, job}} =
               in_session_task(user.id, fn ->
                 Hologram.Job.create(Hologram.Test.Fixtures.Job.Module1, %{}, trust: true)
               end)

      assert %{actor_id: nil, run_as_server: true} = job
    end

    test "keeps the server's authority in a process no session started" do
      row = create_private_row()

      assert in_sandboxed_task(fn -> DB.read(Module1, row.id).id end) == row.id
    end
  end

  # What a check asks is whether a grant EXISTS, so nothing it reads can be gathered - the
  # questions are gathered and answered here, as the session user, so the client's first render
  # can evaluate the same checks against rows rather than waiting for the fill.
  describe "carried_grants/1" do
    test "returns the row answering a check about the session user's own grant" do
      user = create_user("user_80@example.com")
      resource = create_resource()

      grant_role(user, :editor, resource)

      scopes = MapSet.new([{user.id, {:own, Module1, resource.id}}])

      rows = Context.with_actor(user.id, fn -> carried_grants(scopes) end)

      assert [%RoleGrant{user_id: grantee_id, entity_id: entity_id}] = rows
      assert grantee_id == user.id
      assert entity_id == resource.id
    end

    test "answers questions about several resources of one type at once" do
      user = create_user("user_81@example.com")
      resource_1 = create_resource()
      resource_2 = create_resource()

      grant_role(user, :editor, resource_1)
      grant_role(user, :owner, resource_2)

      scopes =
        MapSet.new([
          {user.id, {:own, Module1, resource_1.id}},
          {user.id, {:own, Module1, resource_2.id}}
        ])

      rows = Context.with_actor(user.id, fn -> carried_grants(scopes) end)

      assert length(rows) == 2
    end

    # An own-scope check matches the type-wide row too, which the store keeps apart by a null
    # entity id - so the row answering it has to travel with the rest.
    test "returns the type-wide row an own-scope question also asks about" do
      user = create_user("user_82@example.com")
      resource = create_resource()

      grant_role(user, :editor, Module1)

      scopes = MapSet.new([{user.id, {:own, Module1, resource.id}}])

      rows = Context.with_actor(user.id, fn -> carried_grants(scopes) end)

      assert [%RoleGrant{entity_id: nil}] = rows
    end

    test "returns the row answering a global question" do
      user = create_user("user_83@example.com")

      grant_role(user, Role.Module1)

      scopes = MapSet.new([{user.id, :global}])

      rows = Context.with_actor(user.id, fn -> carried_grants(scopes) end)

      assert [%RoleGrant{entity_type: nil, entity_id: nil}] = rows
    end

    test "returns nothing for a question no grant answers" do
      user = create_user("user_84@example.com")
      resource = create_resource()

      scopes = MapSet.new([{user.id, {:own, Module1, resource.id}}])

      assert Context.with_actor(user.id, fn -> carried_grants(scopes) end) == []
    end

    test "returns nothing when the render asked nothing" do
      user = create_user("user_85@example.com")

      assert Context.with_actor(user.id, fn -> carried_grants(MapSet.new()) end) == []
    end

    # Every grant read rule is actor- or role-shaped, so a visitor holds nothing - the query is
    # skipped rather than run to learn it answers empty.
    test "returns nothing for an anonymous session" do
      user = create_user("user_86@example.com")
      resource = create_resource()

      grant_role(user, :editor, resource)

      scopes = MapSet.new([{user.id, {:own, Module1, resource.id}}])

      assert carried_grants(scopes) == []
    end

    test "returns nothing for a session whose user id no user entity can have" do
      user = create_user("foreign_actor_4@example.com")
      resource = create_resource()

      grant_role(user, :editor, resource)

      scopes = MapSet.new([{user.id, {:own, Module1, resource.id}}])

      assert Context.with_actor(7, fn -> carried_grants(scopes) end) == []
    end

    # The scope says which rows to LOOK FOR, the read policy says which the session user may
    # HOLD - so a question about someone else answers with their row only when the asker's own
    # rules admit it.
    test "withholds another user's row from a session that may not read it" do
      user = create_user("user_87@example.com")
      other_user = create_user("user_88@example.com")
      resource = create_resource()

      grant_role(other_user, :editor, resource)

      scopes = MapSet.new([{other_user.id, {:own, Module1, resource.id}}])

      assert Context.with_actor(user.id, fn -> carried_grants(scopes) end) == []
    end

    test "returns another user's row to a session that may read it" do
      user = create_user("user_89@example.com")
      other_user = create_user("user_90@example.com")
      resource = create_parent()

      grant_role(user, :member, resource)
      grant_role(other_user, :member, resource)

      scopes = MapSet.new([{other_user.id, {:own, Module2, resource.id}}])

      rows = Context.with_actor(user.id, fn -> carried_grants(scopes) end)

      # The asker holds a grant on the same resource, so "their row came back" is not the same
      # answer as "only their row did" - the scope named one user and the reply carries one.
      assert [%RoleGrant{user_id: grantee_id, entity_id: entity_id}] = rows
      assert grantee_id == other_user.id
      assert entity_id == resource.id
    end
  end

  describe "can?/3" do
    test "grants an operation through a rule whose predicates hold" do
      assert can?(nil, :read, %Module1{public: true})
    end

    test "denies an operation when no rule matches" do
      refute can?("02wSyz8E9khZO7aC2RayBN", :read, %Module1{public: false})
    end

    test "denies a framework operation the entity type declares no rule for" do
      refute can?("02wSyz8E9khZO7aC2RayBN", :create, %Module1{public: true})
    end

    test "answers a name by the lines carrying it" do
      owner = create_user("named-owner@example.com")
      other = create_user("named-other@example.com")

      channel =
        [owner_id: owner.id]
        |> Module36.new()
        |> DB.create!()

      assert can?(owner, :archive, channel)
      refute can?(other, :archive, channel)
    end

    test "answers a named line's operation by it as well" do
      owner = create_user("named-operation-owner@example.com")
      other = create_user("named-operation-other@example.com")

      channel =
        [owner_id: owner.id]
        |> Module36.new()
        |> DB.create!()

      assert can?(owner, :update, channel)
      refute can?(other, :update, channel)
    end

    test "delegates to a name the related row's lines carry" do
      owner = create_user("named-delegation-owner@example.com")
      other = create_user("named-delegation-other@example.com")

      channel =
        [owner_id: owner.id]
        |> Module36.new()
        |> DB.create!()

      message =
        [channel_id: channel.id]
        |> Module37.new()
        |> DB.create!()

      assert can?(owner, :moderate, message)
      refute can?(other, :moderate, message)
    end

    # Module36 grants every update of an open channel through a line without the name, which the
    # name doesn't answer by.
    test "answers a name by its own lines alone" do
      owner = create_user("named-alone-owner@example.com")
      other = create_user("named-alone-other@example.com")

      channel =
        [name: "open", owner_id: owner.id]
        |> Module36.new()
        |> DB.create!()

      assert can?(other, :update, channel)
      refute can?(other, :archive, channel)
    end

    # Module37's :moderate line asks the channel's :archive name and its :edit line, a bare via,
    # asks the channel's :update - so on an open channel anyone may edit but only its owner moderate.
    test "delegates to a name alone, and through a bare via to the operation" do
      owner = create_user("named-bare-owner@example.com")
      other = create_user("named-bare-other@example.com")

      channel =
        [name: "open", owner_id: owner.id]
        |> Module36.new()
        |> DB.create!()

      message =
        [channel_id: channel.id]
        |> Module37.new()
        |> DB.create!()

      assert can?(other, :edit, message)
      refute can?(other, :moderate, message)
      assert can?(owner, :moderate, message)
    end

    # A field-limited line holds for this user, but it covers some fields, not the whole row - so
    # neither the update nor a delegation asking it counts it.
    test "counts no field-limited line for a whole-row update" do
      owner = create_user("limited-owner@example.com")
      other = create_user("limited-other@example.com")

      channel =
        [owner_id: owner.id]
        |> Module38.new()
        |> DB.create!()

      message =
        [channel_id: channel.id]
        |> Module39.new()
        |> DB.create!()

      assert can?(other, :set_topic, channel)
      refute can?(other, :update, channel)
      refute can?(other, :update, message)
    end

    test "answers a field through the field-limited lines covering it" do
      user_id = "02wSyz8E9khZO7aC2RayBN"
      channel = %Module38{archived: false, name: "general"}

      assert can?(user_id, {:update, :topic}, channel)
      assert can?(user_id, {:update, :tags}, channel)
      refute can?(user_id, {:update, :name}, channel)
    end

    test "answers a field through the lines covering the whole row" do
      owner_id = "02wSyz8E9khZO7aC2RayBN"
      other_id = "02wSyz8E9khZO7aC2RayBO"
      channel = %Module38{archived: true, name: "general", owner_id: owner_id}

      assert can?(owner_id, {:update, :archived}, channel)
      refute can?(other_id, {:update, :archived}, channel)
    end

    # The except line holds on an open channel and grants what it covers, but leaves :archived out,
    # so only the line covering the whole row can grant that.
    test "answers a field an except line leaves out through the other lines" do
      owner_id = "02wSyz8E9khZO7aC2RayBN"
      other_id = "02wSyz8E9khZO7aC2RayBO"
      channel = %Module38{archived: true, name: "open", owner_id: owner_id}

      assert can?(other_id, {:update, :sent_count}, channel)
      assert can?(owner_id, {:update, :archived}, channel)
      refute can?(other_id, {:update, :archived}, channel)
    end

    # No line that holds here covers both :topic and :name, so the list is granted only by two
    # lines together.
    test "answers a list of fields when some holding line covers each" do
      user_id = "02wSyz8E9khZO7aC2RayBN"
      channel = %Module38{archived: false, name: "general", owner_id: user_id}

      assert can?(user_id, {:update, [:topic, :name]}, channel)
      refute can?(user_id, {:update, [:topic, :owner]}, channel)
    end

    test "raises on a field no update of the entity type sets" do
      expected_msg =
        "unknown field :owner_id in {:update, :owner_id} for Hologram.Test.Fixtures.Policy.Module38 - the fields an update sets are :archived, :name, :owner, :parent, :sent_count, :tags, :topic"

      assert_error MisuseError, expected_msg, fn ->
        can?("02wSyz8E9khZO7aC2RayBN", {:update, :owner_id}, %Module38{})
      end
    end

    test "raises on a list of fields naming one that is not an atom" do
      expected_msg =
        "unknown field 1 in {:update, [1, :topic]} for Hologram.Test.Fixtures.Policy.Module38 - the fields an update sets are :archived, :name, :owner, :parent, :sent_count, :tags, :topic"

      assert_error MisuseError, expected_msg, fn ->
        can?("02wSyz8E9khZO7aC2RayBN", {:update, [1, :topic]}, %Module38{})
      end
    end

    test "raises on an update tuple naming a field that is not an atom" do
      expected_msg =
        "can? takes an operation atom, a {:grant_role, role} / {:revoke_role, role} tuple or an {:update, field} / {:update, fields} tuple"

      assert_error MisuseError, expected_msg, fn ->
        can?("02wSyz8E9khZO7aC2RayBN", {:update, "topic"}, %Module38{})
      end
    end

    test "raises on an improper list of fields" do
      expected_msg =
        "can? takes an operation atom, a {:grant_role, role} / {:revoke_role, role} tuple or an {:update, field} / {:update, fields} tuple"

      assert_error MisuseError, expected_msg, fn ->
        can?("02wSyz8E9khZO7aC2RayBN", {:update, [:topic | :name]}, %Module38{})
      end
    end

    test "raises on an update list naming no field" do
      expected_msg =
        "unknown operation {:update, []} for Hologram.Test.Fixtures.Policy.Module38 - {:update, fields} names at least one field"

      assert_error MisuseError, expected_msg, fn ->
        can?("02wSyz8E9khZO7aC2RayBN", {:update, []}, %Module38{})
      end
    end

    test "matches a rule referencing the acting user" do
      entity = %Module1{author_id: "02wSyz8E9khZO7aC2RayBO"}

      assert can?("02wSyz8E9khZO7aC2RayBO", :archive, entity)
      refute can?("02wSyz8E9khZO7aC2RayBP", :archive, entity)
    end

    # A session's user id may be any string, integer or atom, and one that names no user entity is
    # anonymous to the rules - as somebody holding nothing, an inequality on the acting user would
    # grant it every row it doesn't own. The browser answers the same ids the same way, in
    # describe "a user id in a spelling Hologram doesn't generate" of
    # test/javascript/elixir/hologram/auth_test.mjs. Always update both together.
    test "answers a user id in a spelling Hologram doesn't generate as an anonymous session" do
      unowned = %ReadersModule5{owner_id: nil}

      for user_id <- [
            "018f4571-a1b2-7c3d-8e4f-000000000001",
            "02wSyz8E9khZO7aC2RayBN\n",
            "7n42DGM5Tflk9n8mt7Fhc8",
            "user_id_1",
            7,
            false,
            :admin
          ] do
        assert can?("02wSyz8E9khZO7aC2RayBN", :read, unowned)
        refute can?(user_id, :read, unowned)
        assert can?(user_id, :read, %Module1{public: true})
      end
    end

    test "answers a user struct whose id Hologram doesn't generate as an anonymous session" do
      user = %Module14{id: "018F4571-A1B2-7C3D-8E4F-000000000001"}

      refute can?(user, :read, %ReadersModule5{owner_id: nil})
    end

    test "answers a user struct with no id as an anonymous session" do
      refute can?(%Module14{id: nil}, :read, %ReadersModule5{owner_id: nil})
    end

    test "grants a condition on a path" do
      public_resource =
        %{public: true}
        |> Module1.new()
        |> DB.create!()

      private_resource = create_resource()

      public_middle =
        %{parent_id: public_resource.id}
        |> Module5.new()
        |> DB.create!()

      private_middle =
        %{parent_id: private_resource.id}
        |> Module5.new()
        |> DB.create!()

      assert can?(nil, :read, %Module12{id: Entity.generate_id(), parent_id: public_middle.id})
      refute can?(nil, :read, %Module12{id: Entity.generate_id(), parent_id: private_middle.id})
    end

    # The path leads nowhere, so it reads nil, and nil is not true.
    test "denies a condition on a path that ends nowhere" do
      middle = DB.create!(Module5.new())

      refute can?(nil, :read, %Module12{id: Entity.generate_id(), parent_id: middle.id})
      refute can?(nil, :read, %Module12{id: Entity.generate_id(), parent_id: nil})
    end

    test "takes the user entity" do
      user = Module14.new(email: "user_1@example.com")

      assert can?(user, :archive, %Module1{author_id: user.id})
    end

    test "skips rules referencing the acting user for an anonymous session" do
      refute can?(nil, :archive, %Module1{author_id: nil})
    end

    test "matches an instance grant on the entity" do
      user = create_user("user_41@example.com")
      entity = %Module1{id: Entity.generate_id(), priority: 5}

      refute can?(user, :update, entity)

      grant_role(user, :editor, %Module1{id: entity.id})

      assert can?(user, :update, entity)
    end

    test "matches a type-wide grant on the entity type" do
      user = create_user("user_42@example.com")
      entity = %Module1{id: Entity.generate_id(), priority: 5}

      grant_role(user, :editor, Module1)

      assert can?(user, :update, entity)
    end

    test "matches a role extending the referenced one" do
      user = create_user("user_44@example.com")
      entity = %Module1{id: Entity.generate_id(), priority: 5}

      grant_role(user, :owner, %Module1{id: entity.id})

      assert can?(user, :update, entity)
    end

    test "matches a global role module grant" do
      user = create_user("user_45@example.com")
      entity = %Module2{id: Entity.generate_id()}

      refute can?(user, :archive, entity)

      insert_global_grant(user.id, Role.Module1)

      assert can?(user, :archive, entity)
    end

    test "matches a role module extending the referenced one" do
      user = create_user("user_46@example.com")
      entity = %Module2{id: Entity.generate_id()}

      insert_global_grant(user.id, Role.Module2)

      assert can?(user, :archive, entity)
    end

    test "denies a global role module the acting user does not hold" do
      user = create_user("user_47@example.com")
      other_user = create_user("user_48@example.com")

      insert_global_grant(other_user.id, Role.Module1)

      refute can?(user, :archive, %Module2{id: Entity.generate_id()})
    end

    test "skips global role module rules for an anonymous session" do
      refute can?(nil, :archive, %Module2{id: Entity.generate_id()})
    end

    test "matches a type-wide grant on another entity type" do
      user = create_user("user_45@example.com")
      entity = %Module1{id: Entity.generate_id()}

      refute can?(user, :read, entity)

      grant_role(user, :admin, Module2)

      assert can?(user, :read, entity)
    end

    test "matches a grant on the entity's related instance" do
      user = create_user("user_46@example.com")
      parent = create_parent()
      entity = %Module1{id: Entity.generate_id(), parent_id: parent.id}

      refute can?(user, :delete, entity)

      grant_role(user, :admin, parent)

      assert can?(user, :delete, entity)
    end

    test "denies a related-instance grant reference on an entity without the reference" do
      user = create_user("user_47@example.com")

      grant_role(user, :admin, Module2)

      refute can?(user, :delete, %Module1{id: Entity.generate_id(), parent_id: nil})
    end

    test "matches a grant on the row a path ends at" do
      user = create_user("user_161@example.com")
      {resource, middle} = create_path_rows(nil)
      entity = %Module12{id: Entity.generate_id(), parent_id: middle.id}

      refute can?(user, :update, entity)

      grant_role(user, :viewer, resource)

      assert can?(user, :update, entity)
    end

    test "denies a grant reference whose path ends nowhere" do
      user = create_user("user_162@example.com")
      middle = DB.create!(Module5.new())

      grant_role(user, :viewer, Module1)

      refute can?(user, :update, %Module12{id: Entity.generate_id(), parent_id: middle.id})
    end

    test "delegates to the related entity's policy" do
      public_parent = create_parent(true)
      private_parent = create_parent()

      assert can?(nil, :publish, %Module1{id: Entity.generate_id(), parent_id: public_parent.id})
      refute can?(nil, :publish, %Module1{id: Entity.generate_id(), parent_id: private_parent.id})
    end

    test "denies delegation without the reference" do
      refute can?(nil, :publish, %Module1{id: Entity.generate_id(), parent_id: nil})
    end

    test "delegates through a path" do
      public_parent = create_parent(true)
      private_parent = create_parent()
      {_resource, public_middle} = create_path_rows(public_parent.id)
      {_resource, private_middle} = create_path_rows(private_parent.id)

      assert can?(nil, :publish, %Module12{id: Entity.generate_id(), parent_id: public_middle.id})

      refute can?(nil, :publish, %Module12{id: Entity.generate_id(), parent_id: private_middle.id})
    end

    test "denies a delegation whose path ends nowhere" do
      middle = DB.create!(Module5.new())

      refute can?(nil, :publish, %Module12{id: Entity.generate_id(), parent_id: middle.id})
    end

    test "reads the rows along a path without a lock" do
      parent = create_parent(true)
      {_resource, middle} = create_path_rows(parent.id)

      assert can?(nil, :publish, %Module12{id: Entity.generate_id(), parent_id: middle.id})

      refute "RowShareLock" in relation_lock_modes(Module5)
    end

    # A render's question takes no lock - a lock held from a render would make every page load a
    # lock holder.
    test "reads the related row a delegation reads without a lock" do
      parent = create_parent(true)

      assert can?(nil, :publish, %Module1{id: Entity.generate_id(), parent_id: parent.id})

      refute "RowShareLock" in relation_lock_modes(Module2)
    end

    # The related type's create rule is open, so the refusal before the grant pins that the delegation
    # asks the parent's update rule instead.
    test "grants through the operation a delegation names" do
      user = create_user("user_158@example.com")
      parent = DB.create!(Module10.new())
      entity = %Module11{id: Entity.generate_id(), parent_id: parent.id}

      refute can?(user, :create, entity)

      grant_role(user, :editor, parent)

      assert can?(user, :create, entity)
    end

    test "denies when the operation a delegation names denies" do
      user = create_user("user_159@example.com")

      parent =
        %{archived: true}
        |> Module10.new()
        |> DB.create!()

      grant_role(user, :editor, parent)

      refute can?(user, :create, %Module11{id: Entity.generate_id(), parent_id: parent.id})
    end

    test "answers a grant lifecycle operation for one role" do
      owner = create_user("user_58@example.com")
      editor = create_user("user_59@example.com")
      resource = create_resource()

      grant_role(owner, :owner, resource)
      grant_role(editor, :editor, resource)

      assert can?(owner, {:grant_role, :editor}, resource)
      refute can?(editor, {:grant_role, :editor}, resource)
    end

    test "answers the bare grant lifecycle operation for any role" do
      owner = create_user("user_60@example.com")
      editor = create_user("user_61@example.com")
      resource = create_resource()

      grant_role(owner, :owner, resource)
      grant_role(editor, :editor, resource)

      assert can?(owner, :grant_role, resource)
      refute can?(editor, :grant_role, resource)
    end

    test "raises on a grant lifecycle operation naming several roles" do
      user = create_user("user_62@example.com")
      resource = create_resource()

      expected_msg = "can? asks about one role - {:grant_role, [:editor, :viewer]} names several"

      assert_error MisuseError, expected_msg, fn ->
        can?(user, {:grant_role, [:editor, :viewer]}, resource)
      end
    end

    # IMPORTANT!
    # The shape message is the client's, pinned there by "raises on an operation that is neither an
    # atom nor a role tuple" in test/javascript/elixir/hologram/auth_test.mjs. Always update both.
    test "raises on a role tuple whose members are not atoms" do
      expected_msg =
        "can? takes an operation atom, a {:grant_role, role} / {:revoke_role, role} tuple or an {:update, field} / {:update, fields} tuple"

      assert_error MisuseError, expected_msg, fn ->
        can?("02wSyz8E9khZO7aC2RayBN", {:grant_role, "viewer"}, %Module1{
          public: true
        })
      end
    end

    test "raises on a list in a tuple naming no grant lifecycle operation" do
      expected_msg =
        "can? takes an operation atom, a {:grant_role, role} / {:revoke_role, role} tuple or an {:update, field} / {:update, fields} tuple"

      assert_error MisuseError, expected_msg, fn ->
        can?("02wSyz8E9khZO7aC2RayBN", {:delete, [:public]}, %Module1{
          public: true
        })
      end
    end

    test "raises on a tuple that is not a pair" do
      expected_msg =
        "can? takes an operation atom, a {:grant_role, role} / {:revoke_role, role} tuple or an {:update, field} / {:update, fields} tuple"

      assert_error MisuseError, expected_msg, fn ->
        can?("02wSyz8E9khZO7aC2RayBN", {:grant_role, :editor, :extra}, %Module1{
          public: true
        })
      end
    end

    test "raises on an operation that is neither an atom nor a tuple" do
      expected_msg =
        "can? takes an operation atom, a {:grant_role, role} / {:revoke_role, role} tuple or an {:update, field} / {:update, fields} tuple"

      assert_error MisuseError, expected_msg, fn ->
        can?("02wSyz8E9khZO7aC2RayBN", "read", %Module1{public: true})
      end
    end

    test "raises on an operation the entity type declares no rule for" do
      expected_msg =
        "unknown operation :transfer for Hologram.Test.Fixtures.Policy.Module1 - the framework's operations are :create, :delete, :grant_role, :read, :read_roles, :revoke_role and :update, and its allow lines carry the names :archive and :publish"

      assert_error MisuseError, expected_msg, fn ->
        can?("02wSyz8E9khZO7aC2RayBN", :transfer, %Module1{public: true})
      end
    end

    test "raises on a tuple whose name is not a grant lifecycle operation" do
      expected_msg =
        "unknown operation {:publish, :editor} for Hologram.Test.Fixtures.Policy.Module1 - the operation tuples are {:grant_role, role}, {:revoke_role, role}, {:update, field} and {:update, fields}"

      assert_error MisuseError, expected_msg, fn ->
        can?("02wSyz8E9khZO7aC2RayBN", {:publish, :editor}, %Module1{public: true})
      end
    end

    test "raises on a grant lifecycle operation naming a role the entity type does not declare" do
      expected_msg =
        "unknown role :editr in {:grant_role, :editr} for Hologram.Test.Fixtures.Policy.Module1 - declared roles are: :editor, :maintainer, :owner, :viewer"

      assert_error MisuseError, expected_msg, fn ->
        can?("02wSyz8E9khZO7aC2RayBN", {:grant_role, :editr}, %Module1{public: true})
      end
    end
  end

  describe "can?/3 for the grant store" do
    test "shows a user their own grants" do
      user = create_user("user_50@example.com")

      assert can?(user, :read, %RoleGrant{user_id: user.id})
    end

    test "hides another user's grants without a read-roles role" do
      user = create_user("user_51@example.com")
      other_user = create_user("user_52@example.com")
      resource = create_parent()

      grant = %RoleGrant{
        user_id: other_user.id,
        entity_type: Module2,
        entity_id: resource.id
      }

      refute can?(user, :read, grant)
    end

    test "shows another user's grants to a holder of the resource type's read-roles role" do
      user = create_user("user_53@example.com")
      other_user = create_user("user_54@example.com")
      resource = create_parent()

      grant_role(user, :member, resource)

      grant = %RoleGrant{
        user_id: other_user.id,
        entity_type: Module2,
        entity_id: resource.id
      }

      assert can?(user, :read, grant)
    end

    test "shows another user's grants to a holder of a role that may grant on the resource" do
      admin = create_user("user_63@example.com")
      other_user = create_user("user_64@example.com")
      resource = create_parent()

      grant_role(admin, :admin, resource)

      grant = %RoleGrant{
        user_id: other_user.id,
        entity_type: Module2,
        entity_id: resource.id
      }

      assert can?(admin, :read, grant)
    end

    test "shows another user's grants to a holder of a global role that may grant on the resource" do
      global_holder = create_user("user_88@example.com")
      other_user = create_user("user_89@example.com")
      resource = create_parent()

      grant_role(global_holder, Role.Module1)

      grant = %RoleGrant{
        user_id: other_user.id,
        entity_type: Module2,
        entity_id: resource.id
      }

      assert can?(global_holder, :read, grant)
    end

    test "defaults to the roles that may grant or revoke when read_roles is undeclared" do
      owner = create_user("user_55@example.com")
      editor = create_user("user_56@example.com")
      other_user = create_user("user_57@example.com")
      resource = create_resource()

      grant_role(owner, :owner, resource)
      grant_role(editor, :editor, resource)

      grant = %RoleGrant{
        user_id: other_user.id,
        entity_type: Module1,
        entity_id: resource.id
      }

      assert can?(owner, :read, grant)
      refute can?(editor, :read, grant)
    end

    test "shows a row's grants to a holder of a qualifying role on the whole type" do
      holder = create_user("user_type_wide_1@example.com")
      editor = create_user("user_type_wide_2@example.com")
      other_user = create_user("user_type_wide_3@example.com")
      resource = create_resource()

      grant_role(holder, :owner, Module1)
      grant_role(editor, :editor, Module1)

      row_grant = %RoleGrant{
        user_id: other_user.id,
        entity_type: Module1,
        entity_id: resource.id
      }

      type_wide_grant = %RoleGrant{user_id: other_user.id, entity_type: Module1, entity_id: nil}

      assert can?(holder, :read, row_grant)
      refute can?(editor, :read, row_grant)
      refute can?(holder, :read, type_wide_grant)
    end
  end

  describe "canonical_id/1" do
    test "returns an id in the spelling Hologram generates" do
      id = Entity.generate_id()

      assert canonical_id(id) == id
    end

    test "returns nil for any other value" do
      id = Entity.generate_id()

      for value <- [
            Entity.id_to_uuid(id),
            String.slice(id, 0, 21),
            id <> "\n",
            "7n42DGM5Tflk9n8mt7Fhc8",
            "",
            7,
            false,
            nil
          ] do
        assert canonical_id(value) == nil
      end
    end
  end

  describe "owner_key/1" do
    test "names a visitor as nobody" do
      assert owner_key(nil) == nil
    end

    test "keeps integer ids past 2^53 exact" do
      assert owner_key(9_007_199_254_740_992) == "i9007199254740992"
      assert owner_key(9_007_199_254_740_993) == "i9007199254740993"
    end

    # Browsers keep this text across deploys, so a changed format would strand a user's stored rows
    # and unsent writes.
    test "keeps its exact format" do
      assert owner_key(7) == "i7"
      assert owner_key("abc") == "sabc"

      assert owner_key("02x9QDX4pOzriCIlt0xKjn") == "u02x9QDX4pOzriCIlt0xKjn"
    end

    test "keeps an entity id's leading zeros" do
      assert owner_key("000000002dwHTRTFRxWLTN") == "u000000002dwHTRTFRxWLTN"
    end

    test "keeps the 36-character UUID form as a plain string" do
      assert owner_key("0190c4e2-7c1f-7b3a-9d4e-1a2b3c4d5e6f") ==
               "s0190c4e2-7c1f-7b3a-9d4e-1a2b3c4d5e6f"
    end

    test "keeps an id past the largest 128-bit number as a plain string" do
      assert owner_key("7n42DGM5Tflk9n8mt7Fhc8") == "s7n42DGM5Tflk9n8mt7Fhc8"
    end

    test "keeps an integer and the same digits as a string apart" do
      assert owner_key(1) != owner_key("1")
    end
  end

  describe "can_from?/4" do
    test "answers a user id in a spelling Hologram doesn't generate as an anonymous session" do
      user = create_user("user_168@example.com")
      entity = %Module1{id: Entity.generate_id()}

      grant = %RoleGrant{
        user_id: user.id,
        entity_type: Module1,
        entity_id: entity.id,
        role: :viewer
      }

      assert can_from?(user.id, :read, entity, [grant])
      refute can_from?(Entity.id_to_uuid(user.id), :read, entity, [grant])
      refute can_from?(7, :read, %ReadersModule5{owner_id: nil}, [])
    end

    test "answers from the given grants rather than the stored ones" do
      user = create_user("user_60@example.com")
      entity = %Module1{id: Entity.generate_id()}

      grant = %RoleGrant{
        user_id: user.id,
        entity_type: Module1,
        entity_id: entity.id,
        role: :viewer
      }

      refute can?(user, :read, entity)
      assert can_from?(user, :read, entity, [grant])
    end

    test "denies what the given grants do not hold though the store does" do
      user = create_user("user_61@example.com")
      entity = create_resource()

      grant_role(user, :viewer, entity)

      assert can?(user, :read, entity)
      refute can_from?(user, :read, entity, [])
    end

    test "matches a global grant" do
      user = create_user("user_62@example.com")
      entity = %Module2{id: Entity.generate_id()}

      grant = %RoleGrant{user_id: user.id, role: Role.Module1}

      assert can_from?(user, :archive, entity, [grant])
    end

    test "matches a type-wide grant" do
      user = create_user("user_63@example.com")
      entity = %Module1{id: Entity.generate_id()}

      grant = %RoleGrant{
        user_id: user.id,
        entity_type: Module2,
        role: :admin
      }

      assert can_from?(user, :read, entity, [grant])
    end

    # An own-scope check admits the row's grant AND the type-wide one, which the store's own
    # condition spells as "entity_id = $3 OR entity_id IS NULL".
    test "matches a type-wide grant of the row's own type" do
      user = create_user("user_72@example.com")
      entity = %Module1{id: Entity.generate_id()}

      grant = %RoleGrant{
        user_id: user.id,
        entity_type: Module1,
        role: :viewer
      }

      assert can_from?(user, :read, entity, [grant])
    end

    test "matches a grant on the row itself" do
      user = create_user("user_64@example.com")
      entity = %Module1{id: Entity.generate_id(), priority: 5}

      grant = %RoleGrant{
        user_id: user.id,
        entity_type: Module1,
        entity_id: entity.id,
        role: :editor
      }

      assert can_from?(user, :update, entity, [grant])
    end

    test "matches a grant on a related row" do
      user = create_user("user_65@example.com")
      parent = %Module2{id: Entity.generate_id()}
      entity = %Module1{id: Entity.generate_id(), parent_id: parent.id}

      grant = %RoleGrant{
        user_id: user.id,
        entity_type: Module2,
        entity_id: parent.id,
        role: :admin
      }

      assert can_from?(user, :delete, entity, [grant])
    end

    # A delegation asks the RELATED row's policy, so the list has to reach that far too - a
    # fallback to the store there would judge half the policy under grants nobody asked about.
    test "matches a grant through a delegation" do
      user = create_user("user_66@example.com")
      parent = create_parent()
      entity = %Module4{id: Entity.generate_id(), parent_id: parent.id}

      grant = %RoleGrant{user_id: user.id, role: Role.Module1}

      refute can?(user, :archive, entity)
      assert can_from?(user, :archive, entity, [grant])
    end

    test "reads the related row a delegation reads without a lock" do
      user = create_user("user_157@example.com")
      parent = create_parent()
      grant = %RoleGrant{user_id: user.id, role: Role.Module1}

      assert can_from?(user, :archive, %Module4{id: Entity.generate_id(), parent_id: parent.id}, [
               grant
             ])

      refute "RowShareLock" in relation_lock_modes(Module2)
    end

    test "matches a grant for the grant store's own rows" do
      user = create_user("user_67@example.com")
      other_user = create_user("user_68@example.com")
      resource = create_parent()

      row = %RoleGrant{
        user_id: other_user.id,
        entity_type: Module2,
        entity_id: resource.id
      }

      grant = %RoleGrant{
        user_id: user.id,
        entity_type: Module2,
        entity_id: resource.id,
        role: :member
      }

      refute can_from?(user, :read, row, [])
      assert can_from?(user, :read, row, [grant])
    end

    test "denies a grant held by somebody else" do
      user = create_user("user_69@example.com")
      other_user = create_user("user_70@example.com")
      entity = %Module1{id: Entity.generate_id()}

      grant = %RoleGrant{
        user_id: other_user.id,
        entity_type: Module1,
        entity_id: entity.id,
        role: :viewer
      }

      refute can_from?(user, :read, entity, [grant])
    end

    # A check answered from a list is nobody's question, so a render gathers nothing from it -
    # where the stored check records the scope so the answering row can travel with the page.
    test "records nothing for a render to carry" do
      user = create_user("user_71@example.com")
      entity = %Module1{id: Entity.generate_id()}

      grant = %RoleGrant{
        user_id: user.id,
        entity_type: Module1,
        entity_id: entity.id,
        role: :viewer
      }

      Carry.start()
      assert can_from?(user, :read, entity, [grant])
      assert Carry.take_grant_scopes() == MapSet.new()

      Carry.start()
      refute can?(user, :read, entity)
      # Both of the type's read rules reference a grant, and a stored check records every one it
      # asks - which is what a render needs to carry the rows answering them.
      assert Carry.take_grant_scopes() ==
               MapSet.new([
                 {user.id, {:own, Module1, entity.id}},
                 {user.id, {:type, Module2}}
               ])
    end

    # What :held holds is only visible across sessions - the scratch tier pins that. Here, that it
    # answers what the store answers, for every rule kind.
    test "with :held answers from the store" do
      user = create_user("user_146@example.com")
      other_user = create_user("user_147@example.com")
      entity = %Module1{id: Entity.generate_id(), priority: 5}

      grant_role(user, :editor, %Module1{id: entity.id})

      assert can_from?(user, :update, entity, :held)
      refute can_from?(other_user, :update, entity, :held)
    end

    test "with :held matches a type-wide grant" do
      user = create_user("user_148@example.com")
      entity = %Module1{id: Entity.generate_id(), priority: 5}

      grant_role(user, :editor, Module1)

      assert can_from?(user, :update, entity, :held)
    end

    test "with :held matches a type-wide grant on another entity type" do
      user = create_user("user_152@example.com")

      grant_role(user, :admin, Module2)

      assert can_from?(user, :read, %Module1{id: Entity.generate_id()}, :held)
    end

    test "with :held matches a global role module grant" do
      user = create_user("user_149@example.com")
      entity = %Module2{id: Entity.generate_id()}

      insert_global_grant(user.id, Role.Module1)

      assert can_from?(user, :archive, entity, :held)
    end

    test "with :held matches a grant on a related row" do
      user = create_user("user_150@example.com")
      parent = create_parent()

      grant_role(user, :admin, parent)

      assert can_from?(
               user,
               :delete,
               %Module1{id: Entity.generate_id(), parent_id: parent.id},
               :held
             )

      refute can_from?(user, :delete, %Module1{id: Entity.generate_id(), parent_id: nil}, :held)
    end

    test "with :held follows a delegation" do
      user = create_user("user_151@example.com")
      parent = create_parent()
      entity = %Module4{id: Entity.generate_id(), parent_id: parent.id}

      refute can_from?(user, :archive, entity, :held)

      insert_global_grant(user.id, Role.Module1)

      assert can_from?(user, :archive, entity, :held)
    end

    # A locking read shows in pg_locks as RowShareLock on the relation, even uncontended - the row
    # lock itself, and which mode it is, only the scratch tier sees. Each test is its own sandbox
    # transaction, so a lock one takes is not there in the next.
    test "with :held holds the related row a delegation reads" do
      user = create_user("user_155@example.com")
      parent = create_parent()

      # The answer is false - Module2's :archive wants a global role the user does not hold - and
      # beside the point: the parent row is read before any grant is asked.
      can_from?(user, :archive, %Module4{id: Entity.generate_id(), parent_id: parent.id}, :held)

      assert "RowShareLock" in relation_lock_modes(Module2)
    end

    # The chain's end row is not asserted: the middle row's insert ran its foreign key check, which
    # already holds RowShareLock on the end row's table. The scratch tier proves the far hop.
    test "with :held holds the first related row of a delegation chain" do
      user = create_user("user_156@example.com")

      resource =
        %{public: true}
        |> Module1.new()
        |> DB.create!()

      middle =
        %{parent_id: resource.id}
        |> Module5.new()
        |> DB.create!()

      assert can_from?(
               user,
               :read,
               %Module8{id: Entity.generate_id(), parent_id: middle.id},
               :held
             )

      assert "RowShareLock" in relation_lock_modes(Module5)
    end

    # The answer is false - the user is no editor of the parent - and it would be true if the
    # delegation asked the parent's open create rule.
    test "with :held holds the related row a delegation naming its operation reads" do
      user = create_user("user_160@example.com")
      parent = DB.create!(Module10.new())

      refute can_from?(
               user,
               :create,
               %Module11{id: Entity.generate_id(), parent_id: parent.id},
               :held
             )

      assert "RowShareLock" in relation_lock_modes(Module10)
    end

    # As for a chain of delegations, only the first row is asserted: the inserts of the rows past it
    # already hold RowShareLock on their tables through their foreign key checks.
    test "with :held holds the first row a delegation path reads" do
      parent = create_parent(true)
      {_resource, middle} = create_path_rows(parent.id)
      entity = %Module12{id: Entity.generate_id(), parent_id: middle.id}

      assert can_from?(create_user("user_163@example.com"), :publish, entity, :held)

      assert "RowShareLock" in relation_lock_modes(Module5)
    end

    test "with :held holds the row a grant reference path reads on its way" do
      user = create_user("user_164@example.com")
      {resource, middle} = create_path_rows(nil)

      grant_role(user, :viewer, resource)

      assert can_from?(
               user,
               :update,
               %Module12{id: Entity.generate_id(), parent_id: middle.id},
               :held
             )

      assert "RowShareLock" in relation_lock_modes(Module5)
    end

    # Only the row in between is asserted: the end row's table already holds RowShareLock through
    # the foreign key check of the middle row's insert.
    test "with :held holds the row a condition's path reads on its way" do
      resource =
        %{public: true}
        |> Module1.new()
        |> DB.create!()

      middle =
        %{parent_id: resource.id}
        |> Module5.new()
        |> DB.create!()

      entity = %Module12{id: Entity.generate_id(), parent_id: middle.id}

      assert can_from?(create_user("user_165@example.com"), :read, entity, :held)

      assert "RowShareLock" in relation_lock_modes(Module5)
    end

    test "with :held matches a grant for the grant store's own rows" do
      user = create_user("user_153@example.com")
      other_user = create_user("user_154@example.com")
      resource = create_parent()

      row = %RoleGrant{
        user_id: other_user.id,
        entity_type: Module2,
        entity_id: resource.id
      }

      refute can_from?(user, :read, row, :held)

      grant_role(user, :member, resource)

      assert can_from?(user, :read, row, :held)
    end

    test "with :held answers false for an anonymous session" do
      refute can_from?(nil, :update, %Module1{id: Entity.generate_id(), priority: 5}, :held)
    end
  end

  describe "can_from?/4 for quantified rules over stored rows" do
    defp create_project(values \\ %{}) do
      values
      |> PolicyProject.new()
      |> DB.create!()
    end

    defp create_member(project, seat) do
      %{project_id: project.id, seat: seat}
      |> PolicyMember.new()
      |> DB.create!()
    end

    defp create_label(name) do
      %{name: name}
      |> PolicyLabel.new()
      |> DB.create!()
    end

    defp create_task(values) do
      values
      |> PolicyTask.new()
      |> DB.create!()
    end

    defp create_tag(name) do
      %{name: name}
      |> PolicyTag.new()
      |> DB.create!()
    end

    defp create_card(values) do
      values
      |> PolicyCard.new()
      |> DB.create!()
    end

    test "answers an any over an inverse set of a to-one" do
      project = create_project()
      create_member(project, "half")

      refute can_from?(nil, :update, project, :stored)

      create_member(project, "full")

      assert can_from?(nil, :update, project, :stored)
    end

    test "answers a none over a stored to-many" do
      project = create_project()
      locked = create_label("locked")

      assert can_from?(nil, :archive, project, :stored)

      :ok = EntityOperations.add_relationship(PolicyProject, project.id, :labels, locked.id)

      refute can_from?(nil, :archive, project, :stored)
    end

    test "answers an any over an inverse of a to-many" do
      tag = create_tag("x")
      task = create_task(%{subject: "open"})

      refute can_from?(nil, :read, tag, :stored)

      :ok = EntityOperations.add_relationship(PolicyTask, task.id, :tags, tag.id)

      assert can_from?(nil, :read, tag, :stored)
    end

    test "answers a none over a set read through a to-one" do
      project = create_project()
      task = create_task(%{project_id: project.id})
      locked = create_label("locked")

      assert can_from?(nil, :update, task, :stored)

      :ok = EntityOperations.add_relationship(PolicyProject, project.id, :labels, locked.id)

      refute can_from?(nil, :update, task, :stored)
    end

    # Only the second task holds the tag, so every task's set is read, not the first one's alone.
    test "answers an any over a set read through another set" do
      project = create_project()
      create_task(%{project_id: project.id})
      second_task = create_task(%{project_id: project.id})
      done = create_tag("done")

      refute can_from?(nil, :close, project, :stored)

      :ok = EntityOperations.add_relationship(PolicyTask, second_task.id, :tags, done.id)

      assert can_from?(nil, :close, project, :stored)
    end

    # Every task's shelf is followed to its cards, the second task's among them.
    test "answers a none over a set read through a set and a to-one" do
      project = create_project()
      shelf = DB.create!(PolicyShelf.new())
      create_task(%{project_id: project.id})
      create_task(%{project_id: project.id, shelf_id: shelf.id})

      assert can_from?(nil, :publish, project, :stored)

      create_card(%{flagged: true, shelf_id: shelf.id})

      refute can_from?(nil, :publish, project, :stored)
    end

    # The profile is an inverse holding one row, read on the way to its badges.
    test "answers a none over a set read through an inverse holding one row" do
      project = create_project()

      profile =
        %{project_id: project.id}
        |> PolicyProfile.new()
        |> DB.create!()

      banned = create_label("banned")

      assert can_from?(nil, :feature, project, :stored)

      :ok = EntityOperations.add_relationship(PolicyProfile, profile.id, :badges, banned.id)

      refute can_from?(nil, :feature, project, :stored)
    end

    test "answers an any over a set a row moved out of" do
      project = create_project()
      member = create_member(project, "full")
      other_project = create_project()

      assert can_from?(nil, :update, project, :stored)

      DB.update!(PolicyMember, member.id, project_id: other_project.id)

      refute can_from?(nil, :update, project, :stored)
    end

    # A none rests on the whole set, so :held holds it and share-locks the rows it reads.
    test "answers a none over a stored to-many under :held" do
      project = create_project()
      locked = create_label("locked")

      assert can_from?(nil, :archive, project, :held)

      :ok = EntityOperations.add_relationship(PolicyProject, project.id, :labels, locked.id)

      refute can_from?(nil, :archive, project, :held)
    end

    # A row not created yet has nothing in any set of its.
    test "answers an any asked of a row not created yet false" do
      refute can_from?(nil, :update, %{PolicyProject.new() | id: nil}, :stored)
    end

    test "answers a none asked of a row not created yet true" do
      assert can_from?(nil, :archive, %{PolicyProject.new() | id: nil}, :stored)
    end

    # The board's top two cards by rank leave the flagged one out until it ranks among them.
    test "answers an any over a bounded derived set" do
      board = DB.create!(PolicyBoard.new())
      flagged = create_card(%{board_id: board.id, flagged: true, rank: 1})

      for rank <- [2, 3] do
        create_card(%{board_id: board.id, rank: rank})
      end

      refute can_from?(nil, :read, board, :stored)

      DB.update!(PolicyCard, flagged.id, rank: 4)

      assert can_from?(nil, :read, board, :stored)
    end
  end

  describe "after_checker/2" do
    defp create_channel(name \\ "general") do
      %{name: name}
      |> Channel.new()
      |> DB.create!()
    end

    defp create_message(channel, body) do
      %{body: body, channel_id: channel && channel.id, position: 1}
      |> Message.new()
      |> DB.create!()
    end

    defp create_named_label(name) do
      %{name: name}
      |> Label.new()
      |> DB.create!()
    end

    defp create_target(public) do
      %{public: public}
      |> Module1.new()
      |> DB.create!()
    end

    defp stored(%entity_type{id: id}), do: EntityOperations.get(entity_type, id)

    # Whether the given exact clauses hold for the given stored row under the given change.
    defp holds_after?(clauses, row, values, edges \\ %{}, source \\ :stored) do
      new_row = after_row(row, values, %{}, edges)
      rule = %{exact: %{predicates: clauses}, predicates: [], to: nil, via: nil}

      Evaluator.rule_matches?(rule, row, new_row, nil, after_checker(new_row, source))
    end

    defp none_pinned(source) do
      [{:none, {source, [{:body, :==, "pinned"}]}}]
    end

    defp any_pinned(source) do
      [{:any, {source, [{:body, :==, "pinned"}]}}]
    end

    test "sees a row of the set changing to a value" do
      message = create_message(create_channel(), "plain")

      refute holds_after?(none_pinned({:outer, 1, [:channel, :messages]}), message, %{
               body: "pinned"
             })
    end

    test "sees a row of the set changing away from a value" do
      message = create_message(create_channel(), "pinned")

      assert holds_after?(none_pinned({:outer, 1, [:channel, :messages]}), message, %{
               body: "plain"
             })
    end

    test "reads the stored set from the stored row" do
      message = create_message(create_channel(), "plain")

      assert holds_after?(none_pinned([:channel, :messages]), message, %{body: "pinned"})
    end

    test "sees a row joining the set it moves into" do
      target = create_channel("target")
      message = create_message(create_channel("source"), "pinned")

      assert holds_after?(any_pinned({:outer, 1, [:channel, :messages]}), message, %{
               channel_id: target.id
             })
    end

    test "leaves a row out of the set it moves away from" do
      channel = create_channel()
      label = create_named_label("shared")
      message = create_message(channel, "pinned")
      other = create_message(channel, "plain")
      source = {:outer, 1, [:labels, :messages, :channel, :messages]}
      any_plain = [{:any, {source, [{:body, :==, "plain"}]}}]

      EntityOperations.add_relationship(Message, message.id, :labels, label.id)
      EntityOperations.add_relationship(Message, other.id, :labels, label.id)

      assert holds_after?(any_pinned(source), stored(message), %{})
      refute holds_after?(any_pinned(source), stored(message), %{channel_id: nil})
      assert holds_after?(any_plain, stored(message), %{channel_id: nil})
    end

    test "follows a reference to the changed row as it will be" do
      channel = create_channel("old")
      create_message(channel, "plain")

      clauses = [
        {:any, {{:outer, 1, [:messages]}, [{[:channel, :name], :==, "new"}]}}
      ]

      assert holds_after?(clauses, stored(channel), %{name: "new"})
    end

    test "applies an edge the call adds" do
      label = create_named_label("urgent")
      message = create_message(create_channel(), "plain")
      clauses = [{:any, {{:outer, 1, [:labels]}, [{:name, :==, "urgent"}]}}]

      refute holds_after?(clauses, message, %{})
      assert holds_after?(clauses, message, %{}, %{{:labels, label.id} => :add})
    end

    test "applies an edge the call deletes" do
      label = create_named_label("urgent")
      message = create_message(create_channel(), "plain")
      EntityOperations.add_relationship(Message, message.id, :labels, label.id)
      clauses = [{:any, {{:outer, 1, [:labels]}, [{:name, :==, "urgent"}]}}]

      assert holds_after?(clauses, message, %{})
      refute holds_after?(clauses, message, %{}, %{{:labels, label.id} => :delete})
    end

    test "changes nothing for an add already stored or a delete not stored" do
      kept = create_named_label("urgent")
      absent = create_named_label("other")
      message = create_message(create_channel(), "plain")
      EntityOperations.add_relationship(Message, message.id, :labels, kept.id)
      clauses = [{:any, {{:outer, 1, [:labels]}, [{:name, :==, "urgent"}]}}]

      assert holds_after?(clauses, message, %{}, %{
               {:labels, kept.id} => :add,
               {:labels, absent.id} => :delete
             })
    end

    test "leaves out an added edge's target that is gone" do
      message = create_message(create_channel(), "plain")
      edges = %{{:labels, Entity.generate_id()} => :add}

      assert holds_after?([{:none, {{:outer, 1, [:labels]}, []}}], message, %{}, edges)
    end

    test "overrides a stored pair by the call's edge from the other side of the set" do
      channel = create_channel()
      label = create_named_label("shared")
      message = create_message(channel, "pinned")
      other = create_message(channel, "plain")
      EntityOperations.add_relationship(Message, message.id, :labels, label.id)
      EntityOperations.add_relationship(Message, other.id, :labels, label.id)

      source = {:outer, 1, [:channel, :messages, :labels, :messages]}

      assert holds_after?(any_pinned(source), message, %{})
      refute holds_after?(any_pinned(source), message, %{}, %{{:labels, label.id} => :delete})
    end

    test "carries the change into a nested quantifier" do
      label = create_named_label("urgent")
      message = create_message(create_channel(), "plain")

      clauses = [
        {:any,
         {{:outer, 1, [:channel, :messages]}, [{:any, {[:labels], [{:name, :==, "urgent"}]}}]}}
      ]

      assert holds_after?(clauses, message, %{}, %{{:labels, label.id} => :add})
    end

    test "counts a derived field over the set as the change leaves it" do
      put_derived_definitions([CountedChannel, CountedMessage])

      target =
        %{name: "target"}
        |> CountedChannel.new()
        |> DB.create!()

      message =
        %{body: "plain", position: 1}
        |> CountedMessage.new()
        |> DB.create!()

      clauses = [{{:outer, 1, [:channel, :message_count]}, :==, 1}]

      assert holds_after?(clauses, stored(message), %{channel_id: target.id})
    end

    test "holds the set of a none read whole under :held" do
      message = create_message(create_channel(), "plain")

      assert holds_after?(
               none_pinned({:outer, 1, [:channel, :messages]}),
               message,
               %{body: "other"},
               %{},
               :held
             )

      {class_key, object_key} = SetLock.keys(Channel, message.channel_id)

      statement =
        "SELECT count(*) FROM pg_locks WHERE locktype = 'advisory' AND objsubid = 2 " <>
          "AND pid = pg_backend_pid() AND mode = 'ExclusiveLock' " <>
          "AND classid = $1::bigint::oid AND objid = $2::bigint::oid"

      unsigned = fn key -> if key < 0, do: key + 4_294_967_296, else: key end

      assert {:ok, %Postgrex.Result{rows: [[1]]}} =
               Connection.query(statement, [unsigned.(class_key), unsigned.(object_key)])
    end

    test "asks a role about the row the new reference leads to" do
      user = create_user("after-role@example.com")
      granted = create_target(false)
      other = create_target(false)
      grant_role(user, :editor, granted)

      row = %Module5{id: Entity.generate_id(), parent_id: other.id}
      new_row = after_row(row, %{parent_id: granted.id}, %{}, %{})
      checker = after_checker(new_row, :stored)

      assert checker.({:rel, [:parent], [:editor]}, new_row, user.id)

      refute checker.(
               {:rel, [:parent], [:editor]},
               after_row(row, %{}, %{}, %{}),
               user.id
             )
    end

    test "asks a delegated rule about the stored row when the chain leads back to the changed row" do
      row =
        %{archived: true}
        |> SelfParent.new()
        |> DB.create!()

      new_row = after_row(row, %{archived: false, parent_id: row.id}, %{}, %{})
      checker = after_checker(new_row, :stored)

      refute checker.({:via, :update, [:parent]}, new_row, nil)
    end

    test "asks a delegated rule about the row the new reference leads to" do
      public = create_target(true)
      hidden = create_target(false)

      row = %Module5{id: Entity.generate_id(), parent_id: hidden.id}
      new_row = after_row(row, %{parent_id: public.id}, %{}, %{})
      checker = after_checker(new_row, :stored)

      assert checker.({:via, :read, [:parent]}, new_row, nil)
      refute checker.({:via, :read, [:parent]}, after_row(row, %{}, %{}, %{}), nil)
    end
  end

  describe "after_row/4" do
    test "puts the values and keeps the edges" do
      edges = %{{:labels, "id"} => :add}

      new_row =
        after_row(%Module14{email: "old@example.com"}, %{email: "new@example.com"}, %{}, edges)

      assert new_row.email == "new@example.com"
      assert new_row.__meta__.relationship_ops == edges
    end

    test "moves a counter by its amount" do
      row = %Message{position: 3}

      assert after_row(row, %{}, %{position: -1}, %{}).position == 2
    end
  end

  describe "can?/4 for one specific change" do
    defp create_values_task(values \\ %{}) do
      task =
        values
        |> ChangedTask.new()
        |> DB.create!()

      EntityOperations.get(ChangedTask, task.id)
    end

    defp create_values_project(archived \\ false) do
      %{archived: archived}
      |> ChangedProject.new()
      |> DB.create!()
    end

    defp create_task_admin(task) do
      user = create_user("values-admin@example.com")
      grant_role(user, :admin, task)

      user
    end

    test ":update answers on the row the values leave" do
      task = create_values_task()
      user = create_task_admin(task)

      assert can?(user, :update, task, status: :approved)
      refute can?(user, :update, task, status: :rejected)
    end

    test ":update counts the lines limited to a field, as a write does" do
      task = create_values_task(%{count: 1})

      assert can?(nil, :update, task, count: 10)
      refute can?(nil, :update, task, count: 11)
    end

    test ":update needs every changed field covered" do
      task = create_values_task(%{count: 1})

      refute can?(nil, :update, task, count: 2, status: :approved)
    end

    test "a name asks that name's rules" do
      task = create_values_task()
      user = create_task_admin(task)

      assert can?(user, :approve, task, status: :approved)
      refute can?(user, :approve, task, status: :rejected)
      refute can?(nil, :approve, task, status: :approved)
    end

    test "{:update, field} asks that field's rules" do
      archived = create_values_project(true)
      open = create_values_project()
      task = create_values_task(%{project_id: archived.id})

      assert can?(nil, {:update, :note}, task, note: "x", project_id: open.id)
      refute can?(nil, {:update, :note}, task, note: "x")
    end

    test "{:update, fields} asks every field's rules" do
      task = create_values_task(%{count: 1})
      user = create_task_admin(task)

      assert can?(user, {:update, [:count, :status]}, task, count: 2, status: :approved)
      refute can?(user, {:update, [:count, :status]}, task, count: 11, status: :approved)
    end

    test "takes the values as a map" do
      task = create_values_task(%{count: 1})

      assert can?(nil, :update, task, %{count: 10})
      refute can?(nil, :update, task, %{count: 11})
    end

    test "names a to-one by its reference" do
      user = create_user("values-mover@example.com")
      source = create_values_project()
      granted = create_values_project()
      other = create_values_project()
      task = create_values_task(%{project_id: source.id})
      grant_role(user, :member, source)
      grant_role(user, :member, granted)

      assert can?(user, :update, task, project_id: granted.id)
      refute can?(user, :update, task, project_id: other.id)
    end

    test "reads a value failing its declaration as stored" do
      task = create_values_task()
      user = create_task_admin(task)

      refute can?(user, :update, task, status: :bogus)
    end

    test "reads a reference naming no row as stored" do
      user = create_user("values-missing@example.com")
      project = create_values_project()
      task = create_values_task(%{project_id: project.id})
      grant_role(user, :member, project)

      assert can?(user, :update, task, project_id: Entity.generate_id())
    end

    test "answers a rule with no new() as it stands" do
      user = create_user("values-plain@example.com")
      parent = create_parent()
      grant_role(user, :admin, parent)

      assert can?(user, :update, parent, public: true)
      refute can?(nil, :update, parent, public: true)
    end

    test "writes nothing" do
      task = create_values_task(%{count: 1})

      assert can?(nil, :update, task, count: 10)
      assert EntityOperations.get(ChangedTask, task.id).count == 1
    end

    test "refuses a row carrying recorded changes" do
      task = Query.put_attribute(create_values_task(), :count, 2)

      expected_msg =
        "can? with values asks about a row as stored - #{inspect(ChangedTask)} #{inspect(task.id)} carries recorded changes, so its fields no longer hold the stored values"

      assert_error MisuseError, expected_msg, fn ->
        can?(nil, :update, task, count: 3)
      end
    end

    test "refuses values that are neither a keyword list nor a map" do
      task = create_values_task()

      expected_msg = "can? takes the values of a change as a keyword list or a map - got [1]"

      assert_error MisuseError, expected_msg, fn -> can?(nil, :update, task, [1]) end
    end

    test "refuses a struct as the values" do
      task = create_values_task()

      expected_msg =
        "can? takes the values of a change as a keyword list or a map - got #{inspect(task)}"

      assert_error MisuseError, expected_msg, fn -> can?(nil, :update, task, task) end
    end

    test "refuses a value name DB.update/3 refuses" do
      task = create_values_task()

      expected_msg =
        "invalid changes for #{inspect(ChangedTask)} - only declared attributes and to-one relationships can be updated: :nope"

      assert_error MisuseError, expected_msg, fn -> can?(nil, :update, task, nope: 1) end
    end

    test "refuses a keyword list naming a struct key" do
      task = create_values_task()

      expected_msg =
        "can? takes the values of a change as a keyword list or a map - got [__struct__: URI, count: 1]"

      assert_error MisuseError, expected_msg, fn ->
        can?(nil, :update, task, __struct__: URI, count: 1)
      end
    end

    test "refuses a map naming a struct key" do
      task = create_values_task()

      assert_raise MisuseError, fn -> can?(nil, :update, task, %{__struct__: URI}) end
    end

    test "answers for a row that isn't stored yet" do
      assert can?(nil, {:update, :labels}, %ChangedTask{}, note: "x")
    end

    test "refuses empty values, as DB.update/3 does" do
      task = create_values_task()

      expected_msg =
        "invalid changes for #{inspect(ChangedTask)} - at least one declared attribute or to-one relationship must be changed"

      assert_error MisuseError, expected_msg, fn -> can?(nil, :update, task, []) end
    end

    test "refuses an operation that isn't an update" do
      task = create_values_task()

      expected_msg =
        "can? with values takes :update, the name of an allow :update line, or {:update, field} / {:update, fields} - got :read"

      assert_error MisuseError, expected_msg, fn -> can?(nil, :read, task, count: 1) end
    end

    test "refuses a role operation" do
      task = create_values_task()

      expected_msg =
        "can? with values takes :update, the name of an allow :update line, or {:update, field} / {:update, fields} - got {:grant_role, :admin}"

      assert_error MisuseError, expected_msg, fn ->
        can?(nil, {:grant_role, :admin}, task, count: 1)
      end
    end
  end

  describe "can?/4 for a rule reading the timestamp a write moves" do
    setup do
      task =
        %{}
        |> ChangedTask.new()
        |> DB.create!()

      table = Map.fetch!(DB.mapping(), ChangedTask).table

      {:ok, _result} =
        Connection.query(
          ~s|UPDATE "hologram_data"."#{table}" SET "updated_at" = "updated_at" - interval '1 hour' | <>
            ~s|WHERE "id" = $1|,
          [Codec.encode(task.id, :id)]
        )

      [task: EntityOperations.get(ChangedTask, task.id)]
    end

    test "moves it for a value that can be on the row", %{task: task} do
      assert can?(nil, {:update, :mark}, task, mark: "ok")
    end

    test "leaves it as stored when no value can be on the row", %{task: task} do
      refute can?(nil, {:update, :mark}, task, mark: "too long")
    end
  end

  describe "judged_deltas/2" do
    test "keeps a move to a value the column can hold" do
      row = %ChangedTask{count: 5}

      assert judged_deltas(row, %{count: 2}) == {%{count: 2}, []}
    end

    test "names a move past what the column can hold" do
      row = %ChangedTask{count: 5}

      assert judged_deltas(row, %{count: 9_223_372_036_854_775_807}) == {%{}, [:count]}
    end

    test "names an amount the column can't take, whatever it would move the value to" do
      row = %ChangedTask{count: -5_000_000_000_000_000_000}

      assert judged_deltas(row, %{count: 10_000_000_000_000_000_000}) == {%{}, [:count]}
    end

    test "names a move to a value its declaration refuses" do
      row = %Hologram.Test.Fixtures.Entity.Module10{count: 1}

      assert judged_deltas(row, %{count: -1}) == {%{}, [:count]}
    end
  end

  describe "judged_values/3" do
    test "keeps values the row can hold" do
      project = DB.create!(ChangedProject.new())
      values = %{code: "abc", project_id: project.id}

      assert judged_values(ChangedTask, values, :stored) == {values, [], []}
    end

    test "names a value failing its declaration" do
      assert judged_values(ChangedTask, %{code: "too long", note: "x"}, :stored) ==
               {%{note: "x"}, [:code], []}
    end

    test "names a reference to a row that doesn't exist" do
      values = %{note: "x", project_id: Entity.generate_id()}

      assert judged_values(ChangedTask, values, :stored) == {%{note: "x"}, [], [:project_id]}
    end

    test "names a malformed reference without looking it up" do
      assert judged_values(ChangedTask, %{project_id: "not-a-uuid"}, :stored) ==
               {%{}, [:project_id], []}
    end

    test "keeps a nil reference" do
      assert judged_values(ChangedTask, %{project_id: nil}, :stored) ==
               {%{project_id: nil}, [], []}
    end

    test "holds a reference's target under :held" do
      project = DB.create!(ChangedProject.new())

      statement =
        ~s|SELECT xmax <> '0' FROM "hologram_data"."test_fixtures_policy_module58" WHERE id = $1|

      params = [Codec.encode(project.id, :id)]

      assert {:ok, %Postgrex.Result{rows: [[false]]}} = Connection.query(statement, params)

      assert judged_values(ChangedTask, %{project_id: project.id}, :held) ==
               {%{project_id: project.id}, [], []}

      assert {:ok, %Postgrex.Result{rows: [[true]]}} = Connection.query(statement, params)
    end
  end

  describe "uncovered_fields/5" do
    test "judges a rule reading the row after the change on the given row" do
      task =
        %{count: 9}
        |> ChangedTask.new()
        |> DB.create!()

      row = EntityOperations.get(ChangedTask, task.id)

      assert uncovered_fields(nil, row, [:count], :stored, after_row(row, %{count: 10}, %{}, %{})) ==
               []

      assert uncovered_fields(nil, row, [:count], :stored, after_row(row, %{count: 11}, %{}, %{})) ==
               [:count]
    end

    test "asks whether some change could pass when given no row" do
      task =
        %{count: 11}
        |> ChangedTask.new()
        |> DB.create!()

      assert uncovered_fields(nil, EntityOperations.get(ChangedTask, task.id), [:count], :stored) ==
               []
    end
  end

  describe "chain_target_id/3" do
    test "answers nil for a hop naming a row that is gone" do
      entity = %Module5{parent_id: Entity.generate_id()}

      assert chain_target_id(entity, [:parent, :parent]) == nil
    end

    test "answers nil for an empty hop" do
      assert chain_target_id(%Module5{parent_id: nil}, [:parent]) == nil
    end

    test "answers nil for an empty hop later in the chain" do
      middle = DB.create!(Module1.new())

      assert chain_target_id(%Module5{parent_id: middle.id}, [:parent, :parent]) == nil
    end

    test "answers the id one hop away" do
      target_id = Entity.generate_id()

      assert chain_target_id(%Module5{parent_id: target_id}, [:parent]) == target_id
    end

    test "follows a chain through stored rows" do
      target = create_parent()

      middle =
        %{parent_id: target.id}
        |> Module1.new()
        |> DB.create!()

      assert chain_target_id(%Module5{parent_id: middle.id}, [:parent, :parent]) == target.id
    end

    # The chain's end row is not read: its id is the middle row's reference.
    test "reads the rows along the chain with the given options" do
      target = create_parent()

      middle =
        %{parent_id: target.id}
        |> Module1.new()
        |> DB.create!()

      entity = %Module5{parent_id: middle.id}

      assert chain_target_id(entity, [:parent, :parent], lock: :share) == target.id

      assert "RowShareLock" in relation_lock_modes(Module1)
    end

    test "reads the rows along the chain unlocked by default" do
      target = create_parent()

      middle =
        %{parent_id: target.id}
        |> Module1.new()
        |> DB.create!()

      assert chain_target_id(%Module5{parent_id: middle.id}, [:parent, :parent]) == target.id

      refute "RowShareLock" in relation_lock_modes(Module1)
    end
  end

  describe "grant_role/2" do
    test "mints the row's id from the grant" do
      user = create_user("user_117@example.com")

      grant_role(user, Role.Module1)

      assert grant_id(user.id) == RoleGrant.derive_id(user.id, nil, nil, Role.Module1)
    end

    test "writes a global grant with no resource" do
      user = create_user("user_4@example.com")

      assert grant_role(user, Role.Module1) == :ok

      assert [
               %{
                 entity_type: nil,
                 entity_id: nil,
                 role: "Hologram.Test.Fixtures.Role.Module1"
               }
             ] = grant_rows(user.id)
    end

    test "takes a bare user id" do
      user = create_user("user_5@example.com")

      assert grant_role(user.id, Role.Module1) == :ok

      assert [%{role: "Hologram.Test.Fixtures.Role.Module1"}] = grant_rows(user.id)
    end

    test "keeps the original grant when the user already holds the role" do
      user = create_user("user_49@example.com")

      grant_role(user, Role.Module1)
      [%{created_at: created_at}] = grant_rows(user.id)

      assert grant_role(user, Role.Module1) == :ok

      assert [%{created_at: ^created_at}] = grant_rows(user.id)
    end

    test "raises on a module that is not a global role" do
      user = create_user("user_6@example.com")

      expected_msg =
        "unknown global role Hologram.Test.Fixtures.Entity.Module1 - defined global roles are: Hologram.Test.Fixtures.Role.Module1, Hologram.Test.Fixtures.Role.Module2"

      assert_error MisuseError, expected_msg, fn ->
        grant_role(user, Hologram.Test.Fixtures.Entity.Module1)
      end
    end

    test "raises on an id that is not a canonical entity id" do
      expected_msg =
        "invalid user id \"nope\" - entity ids are strings of 22 base62 characters"

      assert_error MisuseError, expected_msg, fn -> grant_role("nope", Role.Module1) end
    end

    test "raises on a map with no id as the user it is" do
      expected_msg =
        "invalid user id %{} - entity ids are strings of 22 base62 characters"

      assert_error MisuseError, expected_msg, fn -> grant_role(%{}, Role.Module1) end
    end

    test "raises on a canonical id followed by a newline" do
      user = create_user("user_167@example.com")
      user_id = user.id <> "\n"

      expected_msg =
        "invalid user id #{inspect(user_id)} - entity ids are strings of 22 base62 characters"

      assert_error MisuseError, expected_msg, fn -> grant_role(user_id, Role.Module1) end
    end

    test "raises on a user that does not exist" do
      user_id = Entity.generate_id()

      expected_msg =
        "unknown user id #{inspect(user_id)} - roles are granted only to existing users"

      assert_error MisuseError, expected_msg, fn -> grant_role(user_id, Role.Module1) end
    end

    test "raises on a global grant issued by an acting user" do
      granter = create_user("user_22@example.com")
      user = create_user("user_23@example.com")

      expected_msg =
        "global roles are granted only by server code claiming trust: true or running outside a session"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(granter.id, fn -> grant_role(user, Role.Module1) end)
      end
    end

    test "raises on a global grant issued under a user id no user entity can have" do
      user = create_user("foreign_actor_1@example.com")

      expected_msg =
        "global roles are granted only by server code claiming trust: true or running outside a session"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(7, fn -> grant_role(user, Role.Module1) end)
      end
    end

    test "raises on a global grant issued in a signed-out session" do
      user = create_user("signed_out_grant_1@example.com")

      expected_msg =
        "global roles are granted only by server code claiming trust: true or running outside a session"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(nil, fn -> grant_role(user, Role.Module1) end)
      end

      assert grant_rows(user.id) == []
    end
  end

  describe "grant_role/4" do
    test "grants on a row with a trust claim in a signed-out session" do
      user = create_user("trust_grant_1@example.com")
      resource = create_resource()

      result =
        Context.with_actor(nil, fn -> grant_role(user, :owner, resource, trust: true) end)

      assert result == :ok
      assert [%{entity_id: entity_id, granted_by_id: nil}] = grant_rows(user.id)
      assert entity_id == resource.id
    end

    test "grants past the gate with a trust claim, recording no granter" do
      actor = create_user("trust_grant_2@example.com")
      user = create_user("trust_grant_3@example.com")
      resource = create_resource()

      result =
        Context.with_actor(actor.id, fn -> grant_role(user, :owner, resource, trust: true) end)

      assert result == :ok
      assert [%{granted_by_id: nil}] = grant_rows(user.id)
    end

    test "a trust claim leaves the session's user deletable" do
      actor = create_user("trust_grant_13@example.com")
      user = create_user("trust_grant_14@example.com")
      resource = create_resource()

      Context.with_actor(actor.id, fn -> grant_role(user, :owner, resource, trust: true) end)

      assert DB.delete(actor) == :ok
    end

    # A trust grant records no granter because the oplog already says whose request it was.
    test "a trust claim keeps the session's user in the oplog as the actor" do
      actor = create_user("trust_grant_16@example.com")
      user = create_user("trust_grant_17@example.com")
      resource = create_resource()

      Context.with_actor(actor.id, fn -> grant_role(user, :owner, resource, trust: true) end)

      assert [%{actor_id: actor_id, data: %{"granted_by_id" => nil}}] =
               Oplog.read_type_after(RoleGrant, 0, %{"user_id" => user.id})

      assert actor_id == actor.id
    end

    test "grants on a row with a trust claim from a session whose user has no row" do
      user = create_user("trust_grant_12@example.com")
      resource = create_resource()

      assert Context.with_actor("000000001VgEh72lXvTXlK", fn ->
               grant_role(user, :owner, resource, trust: true)
             end) == :ok

      assert [%{granted_by_id: nil}] = grant_rows(user.id)
    end

    test "grants a global role with a trust claim from a session whose user has no row" do
      user = create_user("trust_grant_15@example.com")

      assert Context.with_actor("000000001VgEh72lXvTXlK", fn ->
               grant_role(user, Role.Module1, :global, trust: true)
             end) == :ok

      assert [%{granted_by_id: nil}] = grant_rows(user.id)
    end

    test "grants on a whole type with a trust claim in a session" do
      user = create_user("trust_grant_4@example.com")

      assert Context.with_actor(nil, fn -> grant_role(user, :owner, Module1, trust: true) end) ==
               :ok

      assert [%{entity_id: nil, role: "owner"}] = grant_rows(user.id)
    end

    test "keeps the gate with no options" do
      user = create_user("trust_grant_5@example.com")
      resource = create_resource()

      expected_msg = "a role is granted only by a signed-in user - nobody is signed in"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(nil, fn -> grant_role(user, :owner, resource, []) end)
      end

      assert grant_rows(user.id) == []
    end

    test "raises on any option other than trust: true" do
      user = create_user("trust_grant_6@example.com")
      resource = create_resource()

      expected_msg = "grant_role takes trust: true as its only option, got: [trust: false]"

      assert_error MisuseError, expected_msg, fn ->
        grant_role(user, :owner, resource, trust: false)
      end

      assert grant_rows(user.id) == []
    end

    test "grants a global role with a trust claim in a signed-out session" do
      user = create_user("trust_grant_7@example.com")

      assert Context.with_actor(nil, fn ->
               grant_role(user, Role.Module1, :global, trust: true)
             end) == :ok

      assert [%{entity_id: nil, granted_by_id: nil, role: "Hologram.Test.Fixtures.Role.Module1"}] =
               grant_rows(user.id)
    end

    test "grants a global role with a trust claim under a signed-in user" do
      granter = create_user("trust_grant_8@example.com")
      user = create_user("trust_grant_9@example.com")

      assert Context.with_actor(granter.id, fn ->
               grant_role(user, Role.Module1, :global, trust: true)
             end) == :ok

      assert [%{granted_by_id: nil}] = grant_rows(user.id)
    end

    test "keeps the global gate with an empty option list" do
      user = create_user("trust_grant_10@example.com")

      expected_msg =
        "global roles are granted only by server code claiming trust: true or running outside a session"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(nil, fn -> grant_role(user, Role.Module1, :global, []) end)
      end

      assert grant_rows(user.id) == []
    end

    test "raises on a global grant given an option other than trust: true" do
      user = create_user("trust_grant_11@example.com")

      expected_msg = "grant_role takes trust: true as its only option, got: [nope: true]"

      assert_error MisuseError, expected_msg, fn ->
        grant_role(user, Role.Module1, :global, computed_opts(nope: true))
      end

      assert grant_rows(user.id) == []
    end
  end

  describe "grant_role/3" do
    test "grants a global role given :global" do
      user = create_user("global_scope_1@example.com")

      assert grant_role(user, Role.Module1, :global) == :ok

      assert [%{entity_id: nil, entity_type: nil, granted_by_id: nil}] = grant_rows(user.id)
    end

    test "keeps the global gate given :global in a session" do
      user = create_user("global_scope_2@example.com")

      expected_msg =
        "global roles are granted only by server code claiming trust: true or running outside a session"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(nil, fn -> grant_role(user, Role.Module1, :global) end)
      end

      assert grant_rows(user.id) == []
    end

    # A command can forward browser params as the entity, so a list there must never claim trust.
    test "refuses a trust claim in the entity's place" do
      user = create_user("global_scope_3@example.com")

      expected_msg =
        "grant_role takes an entity, an entity type or :global as its third argument, got: [trust: true] - options go fourth"

      assert_error MisuseError, expected_msg, fn ->
        Context.with_actor(nil, fn ->
          grant_role(user, Role.Module1, computed_opts(trust: true))
        end)
      end

      assert grant_rows(user.id) == []
    end

    test "raises on a grant on a row issued in a signed-out session" do
      user = create_user("signed_out_grant_2@example.com")
      resource = create_resource()

      expected_msg = "a role is granted only by a signed-in user - nobody is signed in"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(nil, fn -> grant_role(user, :owner, resource) end)
      end

      assert grant_rows(user.id) == []
    end

    test "raises on a type-wide grant issued in a signed-out session" do
      user = create_user("signed_out_grant_3@example.com")

      expected_msg =
        "type-wide roles are granted only by server code claiming trust: true or running outside a session"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(nil, fn -> grant_role(user, :owner, Module1) end)
      end

      assert grant_rows(user.id) == []
    end

    # The store has one identity scheme whoever writes it - a grant made here and the same grant
    # made from a browser are one row, and this is the half a command makes.
    test "mints the row's id from the grant" do
      user = create_user("user_116@example.com")
      resource = create_resource()

      grant_role(user, :editor, resource)

      entity_type = Module1

      assert grant_id(user.id) ==
               RoleGrant.derive_id(user.id, entity_type, resource.id, :editor)
    end

    test "writes an instance grant naming the resource type and id" do
      user = create_user("user_7@example.com")

      resource = create_resource()

      assert grant_role(user, :owner, resource) == :ok

      assert [%{entity_type: "Hologram.Test.Fixtures.Policy.Module1", role: "owner"} = grant] =
               grant_rows(user.id)

      assert grant.entity_id == resource.id
    end

    test "writes a type-wide grant with no entity id" do
      user = create_user("user_8@example.com")

      assert grant_role(user, :owner, Module1) == :ok

      assert [
               %{
                 entity_type: "Hologram.Test.Fixtures.Policy.Module1",
                 entity_id: nil,
                 role: "owner"
               }
             ] = grant_rows(user.id)
    end

    test "stamps the acting user as the granter" do
      granter = create_user("user_9@example.com")
      user = create_user("user_10@example.com")

      resource = create_resource()

      grant_role(granter, :owner, resource)

      Context.with_actor(granter.id, fn -> grant_role(user, :editor, resource) end)

      assert [%{granted_by_id: granted_by_id}] = grant_rows(user.id)
      assert granted_by_id == granter.id
    end

    test "leaves the granter unset outside an actor context" do
      user = create_user("user_11@example.com")

      grant_role(user, :owner, Module1)

      assert [%{granted_by_id: nil}] = grant_rows(user.id)
    end

    test "keeps the original grant when the role is already held" do
      granter = create_user("user_12@example.com")
      user = create_user("user_13@example.com")

      resource = create_resource()

      grant_role(granter, :owner, resource)

      Context.with_actor(granter.id, fn -> grant_role(user, :editor, resource) end)
      [original_grant] = grant_rows(user.id)

      assert grant_role(user, :editor, resource) == :ok

      assert grant_rows(user.id) == [original_grant]
    end

    test "grants a role the acting user's role extends" do
      granter = create_user("user_16@example.com")
      user = create_user("user_17@example.com")

      resource = create_resource()

      grant_role(granter, :owner, resource)

      assert Context.with_actor(granter.id, fn -> grant_role(user, :editor, resource) end) == :ok

      assert [%{role: "editor"}] = grant_rows(user.id)
    end

    test "grants the acting user's own role" do
      granter = create_user("user_65@example.com")
      user = create_user("user_66@example.com")

      resource = create_parent()

      grant_role(granter, :member, resource)

      assert Context.with_actor(granter.id, fn -> grant_role(user, :member, resource) end) == :ok

      assert [%{role: "member"}] = grant_rows(user.id)
    end

    test "grants under a global role the line names" do
      granter = create_user("user_77@example.com")
      user = create_user("user_78@example.com")

      resource = create_parent()

      grant_role(granter, Role.Module1)

      assert Context.with_actor(granter.id, fn -> grant_role(user, :admin, resource) end) == :ok

      assert [%{role: "admin"}] = grant_rows(user.id)
    end

    test "grants under a global role extending the one the line names" do
      granter = create_user("user_79@example.com")
      user = create_user("user_80@example.com")

      resource = create_parent()

      grant_role(granter, Role.Module2)

      assert Context.with_actor(granter.id, fn -> grant_role(user, :member, resource) end) ==
               :ok

      assert [%{role: "member"}] = grant_rows(user.id)
    end

    test "grants under a type-wide role" do
      granter = create_user("user_81@example.com")
      user = create_user("user_82@example.com")

      resource = create_resource()

      grant_role(granter, :owner, Module1)

      assert Context.with_actor(granter.id, fn -> grant_role(user, :editor, resource) end) == :ok

      assert [%{role: "editor"}] = grant_rows(user.id)
    end

    test "raises when the acting user holds no role on the resource" do
      granter = create_user("user_18@example.com")
      user = create_user("user_19@example.com")

      resource = create_resource()

      expected_msg =
        "the acting user holds no role on Hologram.Test.Fixtures.Policy.Module1 #{inspect(resource.id)} that may grant :editor"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(granter.id, fn -> grant_role(user, :editor, resource) end)
      end
    end

    test "raises when the acting user id is one no user entity can have" do
      user = create_user("foreign_actor_2@example.com")
      resource = create_resource()

      expected_msg =
        "the acting user holds no role on Hologram.Test.Fixtures.Policy.Module1 #{inspect(resource.id)} that may grant :editor"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(7, fn -> grant_role(user, :editor, resource) end)
      end

      assert grant_rows(user.id) == []
    end

    test "raises when the role is above the acting user's own" do
      granter = create_user("user_67@example.com")
      user = create_user("user_68@example.com")

      resource = create_resource()

      grant_role(granter, :editor, resource)

      expected_msg =
        "the acting user holds :editor on Hologram.Test.Fixtures.Policy.Module1 #{inspect(resource.id)}, " <>
          "which may grant no role there, :owner included. :owner extends :editor, so it holds more. " <>
          "Declare `allow {:grant_role, :owner}, to: :editor` on Hologram.Test.Fixtures.Policy.Module1 if that is intended."

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(granter.id, fn -> grant_role(user, :owner, resource) end)
      end
    end

    test "raises naming what the acting user's role may grant instead" do
      granter = create_user("user_69@example.com")
      user = create_user("user_70@example.com")

      resource = create_parent()

      grant_role(granter, :member, resource)

      expected_msg =
        "the acting user holds :member on Hologram.Test.Fixtures.Policy.Module2 #{inspect(resource.id)}, " <>
          "which may grant :member but not :admin. " <>
          "Declare `allow {:grant_role, :admin}, to: :member` on Hologram.Test.Fixtures.Policy.Module2 if that is intended."

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(granter.id, fn -> grant_role(user, :admin, resource) end)
      end
    end

    test "raises on a type-wide grant issued by an acting user" do
      granter = create_user("user_20@example.com")
      user = create_user("user_21@example.com")

      expected_msg =
        "type-wide roles are granted only by server code claiming trust: true or running outside a session"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(granter.id, fn -> grant_role(user, :owner, Module1) end)
      end
    end

    test "raises on a role the resource type does not declare" do
      user = create_user("user_14@example.com")

      expected_msg =
        "unknown role :publisher for Hologram.Test.Fixtures.Policy.Module1 - declared roles are: :editor, :maintainer, :owner, :viewer"

      assert_error MisuseError, expected_msg, fn -> grant_role(user, :publisher, Module1) end
    end

    test "raises on an entity id that is not a canonical entity id" do
      user = create_user("user_15@example.com")

      expected_msg =
        "invalid entity id \"nope\" - entity ids are strings of 22 base62 characters"

      assert_error MisuseError, expected_msg, fn ->
        grant_role(user, :owner, %Module1{id: "nope"})
      end
    end
  end

  describe "apply_grant_write/3" do
    test "answers :created and writes the grant under a holder who may grant the role" do
      granter = create_user("user_95@example.com")
      user = create_user("user_96@example.com")
      resource = create_resource()

      grant_role(granter, :owner, resource)

      grant =
        grant_struct(
          entity_type: Module1,
          granted_by_id: granter.id,
          entity_id: resource.id,
          role: :editor,
          user_id: user.id
        )

      assert apply_grant_write(grant, granter.id, MapSet.new()) == :created

      assert [row] = grant_rows(user.id)
      assert row.granted_by_id == granter.id
      assert row.entity_id == resource.id
      assert row.role == "editor"
    end

    test "answers :present for a grant the store already holds" do
      granter = create_user("user_97@example.com")
      user = create_user("user_98@example.com")
      resource = create_resource()

      grant_role(granter, :owner, resource)
      grant_role(user, :editor, resource)

      grant =
        grant_struct(
          entity_type: Module1,
          granted_by_id: granter.id,
          entity_id: resource.id,
          role: :editor,
          user_id: user.id
        )

      assert apply_grant_write(grant, granter.id, MapSet.new()) == :present

      assert [%{role: "editor"}] = grant_rows(user.id)
    end

    # granted_to: :creator is a declaration rather than a permission somebody holds, so the grant
    # a browser sends beside its create passes no gate - which is what lets a type declare a
    # creator role without also declaring who may grant it. Module1 lets only an owner grant, and
    # this actor holds nothing there.
    test "writes a creator's grant on a row the batch created, asking no gate" do
      creator = create_user("user_119@example.com")
      resource = create_resource()

      grant =
        grant_struct(
          entity_type: Module1,
          granted_by_id: creator.id,
          entity_id: resource.id,
          role: :maintainer,
          user_id: creator.id
        )

      created = MapSet.new([{Module1, resource.id}])

      assert apply_grant_write(grant, creator.id, created) == :created

      assert [%{role: "maintainer"}] = grant_rows(creator.id)
    end

    # A client is never the trusted tier, so the sentence the verb keeps for an acting user is
    # unconditional here - there is no batch without a session to run it.
    test "refuses a type-wide grant" do
      granter = create_user("user_99@example.com")
      user = create_user("user_100@example.com")

      grant = grant_struct(entity_type: Module1, role: :owner, user_id: user.id)

      expected_msg =
        "type-wide roles are granted only by server code claiming trust: true or running outside a session"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        apply_grant_write(grant, granter.id, MapSet.new())
      end
    end

    test "refuses a global grant" do
      granter = create_user("user_101@example.com")
      user = create_user("user_102@example.com")

      grant = grant_struct(role: Role.Module1, user_id: user.id)

      expected_msg =
        "global roles are granted only by server code claiming trust: true or running outside a session"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        apply_grant_write(grant, granter.id, MapSet.new())
      end
    end

    # Where the verb reads an absent actor as trusted code running a script, a batch has a session
    # behind it either way - so an absent one is an anonymous visitor, who grants nothing.
    test "refuses a grant with nobody signed in" do
      user = create_user("user_103@example.com")
      resource = create_resource()

      grant =
        grant_struct(
          entity_type: Module1,
          entity_id: resource.id,
          role: :editor,
          user_id: user.id
        )

      expected_msg = "a role is granted only by a signed-in user - nobody is signed in"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        apply_grant_write(grant, nil, MapSet.new())
      end
    end

    # The verb raises a Hologram.MisuseError for this; a batch cannot be answered with a raise, so
    # the same violation comes back the way a create naming no row does.
    test "answers the grantee as not found for a user that does not exist" do
      granter = create_user("user_118@example.com")
      resource = create_resource()

      grant_role(granter, :owner, resource)

      grant =
        grant_struct(
          entity_type: Module1,
          granted_by_id: granter.id,
          entity_id: resource.id,
          role: :editor,
          user_id: Entity.generate_id()
        )

      assert apply_grant_write(grant, granter.id, MapSet.new()) ==
               {:error, %{user_id: [:not_found]}}
    end

    test "refuses a role the acting user's own roles do not cover" do
      granter = create_user("user_104@example.com")
      user = create_user("user_105@example.com")
      resource = create_parent()

      grant_role(granter, :member, resource)

      grant =
        grant_struct(
          entity_type: Module2,
          granted_by_id: granter.id,
          entity_id: resource.id,
          role: :admin,
          user_id: user.id
        )

      expected_msg =
        "the acting user holds :member on Hologram.Test.Fixtures.Policy.Module2 #{inspect(resource.id)}, " <>
          "which may grant :member but not :admin. " <>
          "Declare `allow {:grant_role, :admin}, to: :member` on Hologram.Test.Fixtures.Policy.Module2 if that is intended."

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        apply_grant_write(grant, granter.id, MapSet.new())
      end
    end

    # The three parts of a creator's grant, refused one at a time. Each falls back to the gate,
    # which is what an ordinary grant meets - so a browser can send any of these and gets the
    # answer its rules give.
    test "refuses a creator role on a row the batch did not create" do
      creator = create_user("user_120@example.com")
      resource = create_resource()

      grant =
        grant_struct(
          entity_type: Module1,
          granted_by_id: creator.id,
          entity_id: resource.id,
          role: :maintainer,
          user_id: creator.id
        )

      expected_msg =
        "the acting user holds no role on Hologram.Test.Fixtures.Policy.Module1 " <>
          "#{inspect(resource.id)} that may grant :maintainer"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        apply_grant_write(grant, creator.id, MapSet.new())
      end
    end

    test "refuses a creator role granted to anybody but the acting user" do
      creator = create_user("user_121@example.com")
      user = create_user("user_122@example.com")
      resource = create_resource()

      grant =
        grant_struct(
          entity_type: Module1,
          granted_by_id: creator.id,
          entity_id: resource.id,
          role: :maintainer,
          user_id: user.id
        )

      created = MapSet.new([{Module1, resource.id}])

      expected_msg =
        "the acting user holds no role on Hologram.Test.Fixtures.Policy.Module1 " <>
          "#{inspect(resource.id)} that may grant :maintainer"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        apply_grant_write(grant, creator.id, created)
      end
    end

    test "refuses a role the type does not hand its creator" do
      creator = create_user("user_123@example.com")
      resource = create_resource()

      grant =
        grant_struct(
          entity_type: Module1,
          granted_by_id: creator.id,
          entity_id: resource.id,
          role: :editor,
          user_id: creator.id
        )

      created = MapSet.new([{Module1, resource.id}])

      expected_msg =
        "the acting user holds no role on Hologram.Test.Fixtures.Policy.Module1 " <>
          "#{inspect(resource.id)} that may grant :editor"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        apply_grant_write(grant, creator.id, created)
      end
    end
  end

  describe "has_role?/2" do
    test "holds a global role" do
      user = create_user("user_124@example.com")

      insert_global_grant(user.id, Role.Module1)

      assert has_role?(user.id, Role.Module1)
    end

    test "holds the global role an extending module reaches" do
      user = create_user("user_125@example.com")

      insert_global_grant(user.id, Role.Module2)

      assert has_role?(user.id, Role.Module1)
    end

    test "does not hold a global role that extends the held one" do
      user = create_user("user_126@example.com")

      insert_global_grant(user.id, Role.Module1)

      refute has_role?(user.id, Role.Module2)
    end

    test "does not hold a global role granted to another user" do
      user = create_user("user_127@example.com")
      other_user = create_user("user_128@example.com")

      insert_global_grant(other_user.id, Role.Module1)

      refute has_role?(user.id, Role.Module1)
    end

    test "does not hold a global role from a role held on an entity type" do
      user = create_user("user_129@example.com")

      grant_role(user, :admin, Module2)

      refute has_role?(user.id, Role.Module1)
    end

    test "takes the user entity" do
      user = create_user("user_130@example.com")

      insert_global_grant(user.id, Role.Module1)

      assert has_role?(user, Role.Module1)
    end

    test "answers false for an anonymous session" do
      refute has_role?(nil, Role.Module1)
    end

    test "answers false for an id the framework never generated" do
      refute has_role?("not-an-id", Role.Module1)
    end

    # The validator's pattern takes the newline the uuid encoder refuses.
    test "answers false for a canonical id followed by a newline" do
      user = create_user("user_166@example.com")

      grant_role(user, Role.Module1)

      refute has_role?(user.id <> "\n", Role.Module1)
    end

    # A check inside a render is recorded, so the rows answering it travel with the page.
    test "records the question for the render that asked it" do
      user = create_user("user_131@example.com")

      Carry.start()
      refute has_role?(user.id, Role.Module1)

      assert Carry.take_grant_scopes() == MapSet.new([{user.id, :global}])
    end

    test "raises on a module that is not a global role" do
      user = create_user("user_132@example.com")

      expected_msg =
        "unknown global role Hologram.Test.Fixtures.Entity.Module1 - defined global roles are: Hologram.Test.Fixtures.Role.Module1, Hologram.Test.Fixtures.Role.Module2"

      assert_error MisuseError, expected_msg, fn ->
        has_role?(user, Hologram.Test.Fixtures.Entity.Module1)
      end
    end

    # The role is checked before the user, so a mistyped one fails for every session alike.
    test "raises on a module that is not a global role for an anonymous session" do
      expected_msg =
        "unknown global role Hologram.Test.Fixtures.Entity.Module1 - defined global roles are: Hologram.Test.Fixtures.Role.Module1, Hologram.Test.Fixtures.Role.Module2"

      assert_error MisuseError, expected_msg, fn ->
        has_role?(nil, Hologram.Test.Fixtures.Entity.Module1)
      end
    end
  end

  describe "has_role?/3" do
    test "holds a role granted on the row" do
      user = create_user("user_133@example.com")
      resource = create_resource()

      grant_role(user, :editor, resource)

      assert has_role?(user.id, :editor, resource)
    end

    test "holds a role granted on the whole entity type" do
      user = create_user("user_134@example.com")
      resource = create_resource()

      grant_role(user, :editor, Module1)

      assert has_role?(user.id, :editor, resource)
    end

    test "holds the role an extending role reaches" do
      user = create_user("user_135@example.com")
      resource = create_resource()

      grant_role(user, :owner, resource)

      assert has_role?(user.id, :editor, resource)
    end

    test "does not hold a role that extends the held one" do
      user = create_user("user_136@example.com")
      resource = create_resource()

      grant_role(user, :editor, resource)

      refute has_role?(user.id, :owner, resource)
    end

    test "does not hold a role granted on another row" do
      user = create_user("user_137@example.com")
      resource_1 = create_resource()
      resource_2 = create_resource()

      grant_role(user, :editor, resource_1)

      refute has_role?(user.id, :editor, resource_2)
    end

    test "does not hold a role granted to another user" do
      user = create_user("user_138@example.com")
      other_user = create_user("user_139@example.com")
      resource = create_resource()

      grant_role(other_user, :editor, resource)

      refute has_role?(user.id, :editor, resource)
    end

    test "takes the user entity" do
      user = create_user("user_140@example.com")
      resource = create_resource()

      grant_role(user, :editor, resource)

      assert has_role?(user, :editor, resource)
    end

    test "answers false for an anonymous session" do
      resource = create_resource()

      refute has_role?(nil, :editor, resource)
    end

    test "answers false for an id the framework never generated" do
      resource = create_resource()

      refute has_role?("not-an-id", :editor, resource)
    end

    test "answers false for a canonical id followed by a newline" do
      user = create_user("user_169@example.com")
      resource = create_resource()

      grant_role(user, :editor, resource)

      refute has_role?(user.id <> "\n", :editor, resource)
    end

    test "matches the type-wide grant alone on a struct with no id" do
      user = create_user("user_141@example.com")
      resource = create_resource()

      grant_role(user, :editor, resource)

      refute has_role?(user.id, :editor, %Module1{})

      grant_role(user, :viewer, Module1)

      assert has_role?(user.id, :viewer, %Module1{})
    end

    test "asks about the type-wide grant alone when given the entity type" do
      user = create_user("user_142@example.com")
      resource = create_resource()

      grant_role(user, :editor, resource)

      refute has_role?(user.id, :editor, Module1)

      grant_role(user, :editor, Module1)

      assert has_role?(user.id, :editor, Module1)
    end

    # A check inside a render is recorded, so the rows answering it travel with the page.
    test "records the question for the render that asked it" do
      user = create_user("user_143@example.com")
      resource = create_resource()

      Carry.start()
      refute has_role?(user.id, :editor, resource)
      refute has_role?(user.id, :editor, Module1)

      assert Carry.take_grant_scopes() ==
               MapSet.new([
                 {user.id, {:own, Module1, resource.id}},
                 {user.id, {:type, Module1}}
               ])
    end

    test "raises on a role the entity type does not declare" do
      user = create_user("user_144@example.com")
      resource = create_resource()

      expected_msg =
        "unknown role :publisher for Hologram.Test.Fixtures.Policy.Module1 - declared roles are: :editor, :maintainer, :owner, :viewer"

      assert_error MisuseError, expected_msg, fn ->
        has_role?(user, :publisher, resource)
      end
    end

    test "raises on a role for an entity type declaring none" do
      user = create_user("user_145@example.com")

      expected_msg =
        "unknown role :editor for Hologram.Test.Fixtures.Entity.Module4 - declared roles are: "

      assert_error MisuseError, expected_msg, fn ->
        has_role?(user, :editor, %Hologram.Test.Fixtures.Entity.Module4{})
      end
    end

    # The role is checked before the user, so a mistyped one fails for every session alike.
    test "raises on a role the entity type does not declare for an anonymous session" do
      resource = create_resource()

      expected_msg =
        "unknown role :publisher for Hologram.Test.Fixtures.Policy.Module1 - declared roles are: :editor, :maintainer, :owner, :viewer"

      assert_error MisuseError, expected_msg, fn ->
        has_role?(nil, :publisher, resource)
      end
    end
  end

  describe "revoke_role/2" do
    test "removes a global grant" do
      user = create_user("user_24@example.com")
      grant_role(user, Role.Module1)

      assert revoke_role(user, Role.Module1) == :ok
      assert grant_rows(user.id) == []
    end

    # A client watching its own grants learns a row is gone from the round an effect wakes, so a
    # revocation nothing records is one no client hears about until it renders afresh.
    test "records the removal of a global grant" do
      user = create_user("user_51@example.com")
      grant_role(user, Role.Module1)
      revoked_id = grant_id(user.id)

      revoke_role(user, Role.Module1)

      assert revocation_effects() == [{"Hologram.Auth.RoleGrant", revoked_id}]
    end

    test "is a no-op for a role the user does not hold" do
      user = create_user("user_25@example.com")

      assert revoke_role(user, Role.Module1) == :ok
      assert grant_rows(user.id) == []
      assert revocation_effects() == []
    end

    test "raises on a module that is not a global role" do
      user = create_user("user_50@example.com")

      expected_msg =
        "unknown global role Hologram.Test.Fixtures.Entity.Module1 - defined global roles are: Hologram.Test.Fixtures.Role.Module1, Hologram.Test.Fixtures.Role.Module2"

      assert_error MisuseError, expected_msg, fn ->
        revoke_role(user, Hologram.Test.Fixtures.Entity.Module1)
      end
    end

    test "raises on a global revocation issued by an acting user" do
      granter = create_user("user_26@example.com")
      user = create_user("user_27@example.com")

      expected_msg =
        "global roles are revoked only by server code claiming trust: true or running outside a session"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(granter.id, fn -> revoke_role(user, Role.Module1) end)
      end
    end

    test "raises on a global revocation issued in a signed-out session" do
      user = create_user("signed_out_revoke_1@example.com")

      grant_role(user, Role.Module1)

      expected_msg =
        "global roles are revoked only by server code claiming trust: true or running outside a session"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(nil, fn -> revoke_role(user, Role.Module1) end)
      end

      assert [_grant] = grant_rows(user.id)
    end
  end

  describe "revoke_role/4" do
    test "revokes on a row with a trust claim in a signed-out session" do
      user = create_user("trust_revoke_1@example.com")
      resource = create_resource()

      grant_role(user, :owner, resource)

      assert Context.with_actor(nil, fn -> revoke_role(user, :owner, resource, trust: true) end) ==
               :ok

      assert grant_rows(user.id) == []
    end

    test "revokes past the gate with a trust claim under a signed-in user" do
      actor = create_user("trust_revoke_2@example.com")
      user = create_user("trust_revoke_3@example.com")
      resource = create_resource()

      grant_role(user, :owner, resource)

      assert Context.with_actor(actor.id, fn ->
               revoke_role(user, :owner, resource, trust: true)
             end) == :ok

      assert grant_rows(user.id) == []
    end

    test "revokes on a whole type with a trust claim in a session" do
      user = create_user("trust_revoke_4@example.com")

      grant_role(user, :owner, Module1)

      assert Context.with_actor(nil, fn -> revoke_role(user, :owner, Module1, trust: true) end) ==
               :ok

      assert grant_rows(user.id) == []
    end

    test "keeps the gate with no options" do
      user = create_user("trust_revoke_5@example.com")
      resource = create_resource()

      grant_role(user, :owner, resource)

      expected_msg = "a role is revoked only by a signed-in user - nobody is signed in"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(nil, fn -> revoke_role(user, :owner, resource, []) end)
      end

      assert [_grant] = grant_rows(user.id)
    end

    test "raises on any option other than trust: true" do
      user = create_user("trust_revoke_6@example.com")
      resource = create_resource()

      grant_role(user, :owner, resource)

      expected_msg = "revoke_role takes trust: true as its only option, got: [trust: false]"

      assert_error MisuseError, expected_msg, fn ->
        revoke_role(user, :owner, resource, trust: false)
      end

      assert [_grant] = grant_rows(user.id)
    end

    test "revokes a global role with a trust claim in a signed-out session" do
      user = create_user("trust_revoke_7@example.com")

      grant_role(user, Role.Module1)

      assert Context.with_actor(nil, fn ->
               revoke_role(user, Role.Module1, :global, trust: true)
             end) == :ok

      assert grant_rows(user.id) == []
    end

    test "revokes a global role with a trust claim under a signed-in user" do
      actor = create_user("global_scope_4@example.com")
      user = create_user("global_scope_5@example.com")

      grant_role(user, Role.Module1)

      assert Context.with_actor(actor.id, fn ->
               revoke_role(user, Role.Module1, :global, trust: true)
             end) == :ok

      assert grant_rows(user.id) == []
    end

    test "keeps the global gate with an empty option list" do
      user = create_user("trust_revoke_8@example.com")

      grant_role(user, Role.Module1)

      expected_msg =
        "global roles are revoked only by server code claiming trust: true or running outside a session"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(nil, fn -> revoke_role(user, Role.Module1, :global, []) end)
      end

      assert [_grant] = grant_rows(user.id)
    end

    test "raises on a global revocation given an option other than trust: true" do
      user = create_user("global_scope_7@example.com")

      grant_role(user, Role.Module1)

      expected_msg = "revoke_role takes trust: true as its only option, got: [nope: true]"

      assert_error MisuseError, expected_msg, fn ->
        revoke_role(user, Role.Module1, :global, computed_opts(nope: true))
      end

      assert [_grant] = grant_rows(user.id)
    end
  end

  describe "revoke_role/3" do
    test "revokes a global role given :global" do
      user = create_user("global_scope_6@example.com")

      grant_role(user, Role.Module1)

      assert revoke_role(user, Role.Module1, :global) == :ok
      assert grant_rows(user.id) == []
    end

    test "keeps the global gate given :global in a session" do
      user = create_user("global_scope_9@example.com")

      grant_role(user, Role.Module1)

      expected_msg =
        "global roles are revoked only by server code claiming trust: true or running outside a session"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(nil, fn -> revoke_role(user, Role.Module1, :global) end)
      end

      assert [_grant] = grant_rows(user.id)
    end

    # A command can forward browser params as the entity, so a list there must never claim trust.
    test "refuses a trust claim in the entity's place" do
      user = create_user("global_scope_8@example.com")

      grant_role(user, Role.Module1)

      expected_msg =
        "revoke_role takes an entity, an entity type or :global as its third argument, got: [trust: true] - options go fourth"

      assert_error MisuseError, expected_msg, fn ->
        Context.with_actor(nil, fn ->
          revoke_role(user, Role.Module1, computed_opts(trust: true))
        end)
      end

      assert [_grant] = grant_rows(user.id)
    end

    test "raises on a revocation on a row issued in a signed-out session" do
      user = create_user("signed_out_revoke_2@example.com")
      resource = create_resource()

      grant_role(user, :owner, resource)

      expected_msg = "a role is revoked only by a signed-in user - nobody is signed in"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(nil, fn -> revoke_role(user, :owner, resource) end)
      end

      assert [_grant] = grant_rows(user.id)
    end

    test "raises on a type-wide revocation issued in a signed-out session" do
      user = create_user("signed_out_revoke_3@example.com")

      grant_role(user, :owner, Module1)

      expected_msg =
        "type-wide roles are revoked only by server code claiming trust: true or running outside a session"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(nil, fn -> revoke_role(user, :owner, Module1) end)
      end

      assert [_grant] = grant_rows(user.id)
    end

    test "raises on a canonical id followed by a newline" do
      user = create_user("user_170@example.com")
      resource = create_resource()
      user_id = user.id <> "\n"

      expected_msg =
        "invalid user id #{inspect(user_id)} - entity ids are strings of 22 base62 characters"

      assert_error MisuseError, expected_msg, fn -> revoke_role(user_id, :owner, resource) end
    end

    test "removes an instance grant" do
      user = create_user("user_28@example.com")
      resource = create_resource()

      grant_role(user, :owner, resource)

      assert revoke_role(user, :owner, resource) == :ok
      assert grant_rows(user.id) == []
    end

    test "records the removal of an instance grant" do
      user = create_user("user_52@example.com")
      resource = create_resource()

      grant_role(user, :owner, resource)
      revoked_id = grant_id(user.id)

      revoke_role(user, :owner, resource)

      assert revocation_effects() == [{"Hologram.Auth.RoleGrant", revoked_id}]
    end

    test "lets a user revoke their own role" do
      owner = create_user("user_29@example.com")
      member = create_user("user_30@example.com")
      resource = create_resource()

      grant_role(owner, :owner, resource)
      grant_role(member, :editor, resource)

      assert Context.with_actor(member.id, fn -> revoke_role(member, :editor, resource) end) ==
               :ok

      assert grant_rows(member.id) == []
    end

    test "removes another user's role the acting user's role extends" do
      owner = create_user("user_31@example.com")
      member = create_user("user_32@example.com")
      resource = create_resource()

      grant_role(owner, :owner, resource)
      grant_role(member, :editor, resource)

      assert Context.with_actor(owner.id, fn -> revoke_role(member, :editor, resource) end) == :ok

      assert grant_rows(member.id) == []
    end

    test "removes another user's role equal to the acting user's own" do
      member = create_user("user_71@example.com")
      other_member = create_user("user_72@example.com")
      resource = create_parent()

      grant_role(member, :member, resource)
      grant_role(other_member, :member, resource)

      assert Context.with_actor(member.id, fn ->
               revoke_role(other_member, :member, resource)
             end) == :ok

      assert grant_rows(other_member.id) == []
    end

    test "removes another user's role under a global role the line names" do
      admin = create_user("user_83@example.com")
      member = create_user("user_84@example.com")
      global_holder = create_user("user_85@example.com")
      resource = create_parent()

      grant_role(admin, :admin, resource)
      grant_role(member, :member, resource)
      grant_role(global_holder, Role.Module1)

      assert Context.with_actor(global_holder.id, fn ->
               revoke_role(member, :member, resource)
             end) == :ok

      assert grant_rows(member.id) == []
    end

    test "raises when the acting user holds no role on the resource" do
      member = create_user("user_73@example.com")
      other_user = create_user("user_74@example.com")
      resource = create_resource()

      grant_role(member, :editor, resource)

      expected_msg =
        "the acting user holds no role on Hologram.Test.Fixtures.Policy.Module1 #{inspect(resource.id)} that may revoke :editor"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(other_user.id, fn -> revoke_role(member, :editor, resource) end)
      end
    end

    test "raises when the acting user id is one no user entity can have" do
      member = create_user("foreign_actor_3@example.com")
      resource = create_resource()

      grant_role(member, :editor, resource)

      expected_msg =
        "the acting user holds no role on Hologram.Test.Fixtures.Policy.Module1 #{inspect(resource.id)} that may revoke :editor"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor("abc", fn -> revoke_role(member, :editor, resource) end)
      end

      assert [%{role: "editor"}] = grant_rows(member.id)
    end

    test "raises when the acting user's role may not revoke it" do
      member = create_user("user_33@example.com")
      other_member = create_user("user_34@example.com")
      resource = create_resource()

      grant_role(member, :editor, resource)
      grant_role(other_member, :editor, resource)

      expected_msg =
        "the acting user holds :editor on Hologram.Test.Fixtures.Policy.Module1 #{inspect(resource.id)}, " <>
          "which may revoke no role there, :editor included. " <>
          "Declare `allow {:revoke_role, :editor}, to: :editor` on Hologram.Test.Fixtures.Policy.Module1 if that is intended."

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(other_member.id, fn -> revoke_role(member, :editor, resource) end)
      end
    end

    test "raises when the role is above the acting user's own" do
      owner = create_user("user_75@example.com")
      editor = create_user("user_76@example.com")
      resource = create_resource()

      grant_role(owner, :owner, resource)
      grant_role(editor, :editor, resource)

      expected_msg =
        "the acting user holds :editor on Hologram.Test.Fixtures.Policy.Module1 #{inspect(resource.id)}, " <>
          "which may revoke no role there, :owner included. :owner extends :editor, so it holds more. " <>
          "Declare `allow {:revoke_role, :owner}, to: :editor` on Hologram.Test.Fixtures.Policy.Module1 if that is intended."

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(editor.id, fn -> revoke_role(owner, :owner, resource) end)
      end
    end

    test "raises on a type-wide revocation issued by an acting user" do
      granter = create_user("user_39@example.com")
      user = create_user("user_40@example.com")

      expected_msg =
        "type-wide roles are revoked only by server code claiming trust: true or running outside a session"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(granter.id, fn -> revoke_role(user, :owner, Module1) end)
      end
    end
  end

  describe "apply_revocation_write/2" do
    # An editor may not revoke on Module1 - the rule names :owner - so this passes only because the
    # row is the actor's own, which is how a member leaves a resource.
    test "revokes the acting user's own row without asking the gate" do
      owner = create_user("user_106@example.com")
      editor = create_user("user_107@example.com")
      resource = create_resource()

      grant_role(owner, :owner, resource)
      grant_role(editor, :editor, resource)

      grant = held_grant(editor.id)

      assert apply_revocation_write(grant, editor.id) == :ok
      assert grant_rows(editor.id) == []
    end

    test "revokes another user's row under a role that may" do
      owner = create_user("user_108@example.com")
      editor = create_user("user_109@example.com")
      resource = create_resource()

      grant_role(owner, :owner, resource)
      grant_role(editor, :editor, resource)

      grant = held_grant(editor.id)

      assert apply_revocation_write(grant, owner.id) == :ok
      assert grant_rows(editor.id) == []
    end

    test "refuses another user's row under a role that may not" do
      first_editor = create_user("user_110@example.com")
      second_editor = create_user("user_111@example.com")
      resource = create_resource()

      grant_role(first_editor, :editor, resource)
      grant_role(second_editor, :editor, resource)

      grant = held_grant(second_editor.id)

      expected_msg =
        "the acting user holds :editor on Hologram.Test.Fixtures.Policy.Module1 #{inspect(resource.id)}, " <>
          "which may revoke no role there, :editor included. " <>
          "Declare `allow {:revoke_role, :editor}, to: :editor` on Hologram.Test.Fixtures.Policy.Module1 if that is intended."

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        apply_revocation_write(grant, first_editor.id)
      end
    end

    test "refuses a type-wide revocation" do
      actor = create_user("user_113@example.com")
      user = create_user("user_114@example.com")

      grant_role(user, :owner, Module1)

      grant = held_grant(user.id)

      expected_msg =
        "type-wide roles are revoked only by server code claiming trust: true or running outside a session"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        apply_revocation_write(grant, actor.id)
      end
    end

    test "refuses a revocation with nobody signed in" do
      user = create_user("user_115@example.com")
      resource = create_resource()

      grant_role(user, :owner, resource)

      grant = held_grant(user.id)

      expected_msg = "a role is revoked only by a signed-in user - nobody is signed in"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        apply_revocation_write(grant, nil)
      end
    end
  end

  describe "user_id/0" do
    test "returns the actor of the calling process" do
      assert Context.with_actor("user_id_1", fn -> user_id() end) == "user_id_1"
    end

    test "returns nil for an anonymous session" do
      assert user_id() == nil
    end
  end

  # A row not created yet has nothing in any set of its, so its verdicts are answered without a
  # read - the sets of a row as stored are read through the same checker can?/3 uses.
  describe "verdicts/2" do
    defmodule VerdictBoard do
      use Hologram.Entity

      relationship :cards, [Hologram.AuthTest.VerdictCard], inverse: board

      allow :read
      allow :delete, when: none(cards)
      allow :update, as: :archive, when: none(card <- cards, card.author_id == user_id())
      allow :update, when: any(card <- cards, card.author_id == user_id())
    end

    defmodule VerdictCard do
      use Hologram.Entity

      relationship :author, Module14, optional: true
      relationship :board, VerdictBoard, optional: true

      allow :read
    end

    defmodule VerdictReport do
      use Hologram.Entity

      attribute :owner_id, :id, optional: true
      attribute :reviewed, :boolean, server_only: true

      allow :read, when: reviewed == true or owner_id == user_id()
    end

    defp board_verdicts(answers) do
      Map.new(answers, fn {operation, answer} ->
        {Policy.verdict_key(VerdictBoard, operation), answer}
      end)
    end

    # The archive line is a named update line, so its none answers the update operation too - which
    # its any answers otherwise.
    test "answers each operation of the row's type for the user" do
      user_id = Entity.generate_id()

      assert verdicts(user_id, %VerdictBoard{}) ==
               board_verdicts(archive: true, delete: true, update: true)
    end

    # Nobody wrote no card on an empty board, but the archive rule asks about nobody, which grants
    # nothing.
    test "answers a visitor's none naming the actor false" do
      assert verdicts(nil, %VerdictBoard{}) ==
               board_verdicts(archive: false, delete: true, update: false)
    end

    test "answers a user id in a spelling Hologram doesn't generate as a visitor's" do
      user_id = Entity.generate_id()

      for other_spelling <- [Entity.id_to_uuid(user_id), 7, false] do
        assert verdicts(other_spelling, %VerdictBoard{}) == verdicts(nil, %VerdictBoard{})
      end
    end

    # The owner reads the report whether it is reviewed or not, and is told nothing more: the
    # server-only value stays on the server.
    test "answers the read verdict true whatever a server-only attribute holds" do
      owner_id = Entity.generate_id()
      key = Policy.verdict_key(VerdictReport, :read)

      for reviewed? <- [false, true] do
        report = %VerdictReport{owner_id: owner_id, reviewed: reviewed?}

        assert verdicts(owner_id, report) == %{key => true}
      end
    end

    test "answers nothing for a type the server sends no verdict on" do
      assert verdicts(nil, %Module14{}) == %{}
    end
  end

  describe "verdicts/2 for stored rows" do
    defp policy_verdicts(answers) do
      Map.new(answers, fn {operation, answer} ->
        {Policy.verdict_key(PolicyProject, operation), answer}
      end)
    end

    # The field's verdict answers every line covering it, so it holds while the feature line does,
    # though the archive line no longer holds once the project has a locked label. The close, read
    # and whole-row update lines read the project's tasks and members, which a reader may not hold.
    test "answers each operation over the rows as stored" do
      project = DB.create!(PolicyProject.new())

      locked =
        %{name: "locked"}
        |> PolicyLabel.new()
        |> DB.create!()

      assert verdicts(nil, project) ==
               policy_verdicts([
                 {:archive, true},
                 {:close, false},
                 {:feature, true},
                 {:publish, true},
                 {:read, true},
                 {:update, false},
                 {{:update, :name}, true}
               ])

      :ok = EntityOperations.add_relationship(PolicyProject, project.id, :labels, locked.id)

      assert verdicts(nil, project) ==
               policy_verdicts([
                 {:archive, false},
                 {:close, false},
                 {:feature, true},
                 {:publish, true},
                 {:read, true},
                 {:update, false},
                 {{:update, :name}, true}
               ])
    end

    # Only a workshop's owner and members read it, its benches and its tools' permits. Alice edits
    # the bench's workshop and Bob the tool's, which is archived, and the tool has an approved
    # permit: the server reads each related row as stored, whoever may read it.
    test "answers the operations reading related rows a reader may not hold over the rows as stored" do
      alice = create_user("workshop_alice@example.com")
      bob = create_user("workshop_bob@example.com")

      create = fn entity_type, values ->
        values
        |> entity_type.new()
        |> DB.create!()
      end

      tool_workshop = create.(Module46, %{archived: true})
      bench_workshop = create.(Module46, %{})
      bench = create.(Module47, %{workshop_id: bench_workshop.id})
      tool = create.(Module49, %{bench_id: bench.id, workshop_id: tool_workshop.id})
      create.(Module48, %{approved: true, tool_id: tool.id})

      grant_role(alice, :editor, bench_workshop)
      grant_role(bob, :editor, tool_workshop)

      answers = fn delete?, label? ->
        Map.new(
          [
            {:delete, delete?},
            {:draft, false},
            {:read, true},
            {:update, false},
            {{:update, :bench}, true},
            {{:update, :label}, label?}
          ],
          fn {operation, answer} -> {Policy.verdict_key(Module49, operation), answer} end
        )
      end

      assert verdicts(alice.id, tool) == answers.(false, true)
      assert verdicts(bob.id, tool) == answers.(true, false)
      assert verdicts(nil, tool) == answers.(false, false)
    end

    # No client holds a project, a vault or a shelf, so the server answers the read rules reading
    # them - and tells each reader only that they may read the row, whichever rule lets them.
    test "answers the read verdict true for read rules through a type nobody may read" do
      keeper = create_user("verdict_keeper@example.com")

      create = fn entity_type, values ->
        values
        |> entity_type.new()
        |> DB.create!()
      end

      archived = create.(ReadersModule20, %{archived: true, steward_id: keeper.id})
      task = create.(ReadersModule21, %{project_id: archived.id})
      vault = create.(ReadersModule25, %{keeper_id: keeper.id})
      parcel = create.(ReadersModule28, %{vault_id: vault.id})

      grant_role(keeper, :member, vault)

      assert verdicts(keeper.id, task) == %{Policy.verdict_key(ReadersModule21, :read) => true}
      assert verdicts(keeper.id, parcel) == %{Policy.verdict_key(ReadersModule28, :read) => true}
    end
  end
end
