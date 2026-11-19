defmodule Hologram.Sync.FillTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.DB.EntityOperations, only: [add_relationship: 4]
  import Hologram.Sync.Fill

  alias Hologram.Auth
  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.Mutation.Record
  alias Hologram.Query.Stage
  alias Hologram.Sync.PackedIds
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module26
  alias Hologram.Test.Fixtures.Entity.Module27
  alias Hologram.Test.Fixtures.Entity.Module28
  alias Hologram.Test.Fixtures.Entity.Module29
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1
  alias Hologram.Test.Fixtures.Policy.Module3, as: PolicyModule3

  @replica_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e0f"

  defp confirmed(replica_id, seq) do
    Connection.transaction(fn ->
      Record.claim!(replica_id, seq, nil, "h")
      Record.complete!(replica_id, seq, %{"dropped" => %{}, "status" => "confirmed"})
    end)
  end

  defp label(name) do
    %{name: name}
    |> Module29.new()
    |> DB.create!()
  end

  defp message(body) do
    %{body: body, position: 1}
    |> Module28.new()
    |> DB.create!()
  end

  defp policy_entity(public) do
    %{public: public}
    |> PolicyModule1.new()
    |> DB.create!()
  end

  defp policy_user(email) do
    %{email: email}
    |> Module14.new()
    |> DB.create!()
  end

  defp sorted_ids(rows) do
    rows
    |> Enum.map(& &1.id)
    |> Enum.sort()
  end

  describe "read/4" do
    # A visitor is read through the read rules, never through the trusted tier, which would read
    # every row.
    test "answers the rows of the type the user may read" do
      public = policy_entity(true)
      policy_entity(false)

      {rows, _applied_seq} = read(PolicyModule1, nil, nil, [PolicyModule1])

      assert sorted_ids(rows) == [public.id]
    end

    test "answers the rows granted to the given user" do
      user = policy_user("fill_1@example.com")
      public = policy_entity(true)
      granted = policy_entity(false)
      policy_entity(false)

      Auth.grant_role(user, :viewer, granted)

      {rows, _applied_seq} = read(PolicyModule1, user.id, nil, [PolicyModule1])

      assert sorted_ids(rows) == Enum.sort([public.id, granted.id])
    end

    # The sandbox makes every read here a savepoint of the test's transaction, so this one runs in a
    # process outside it, which opens a transaction of its own - read only, which the read has to
    # work under. The rows the other tests wrote are uncommitted, so it reads none.
    test "reads outside any transaction" do
      test_pid = self()

      {pid, ref} =
        spawn_monitor(fn ->
          send(test_pid, {:read, read(PolicyModule1, nil, @replica_id, [PolicyModule1])})
        end)

      assert_receive {:read, {[], nil}}, 5_000
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000
    end

    test "answers no rows for a type the user may read none of" do
      policy_entity(false)

      assert read(PolicyModule1, nil, nil, [PolicyModule1]) == {[], nil}
    end

    test "includes only the targets of a set the user may read" do
      public = policy_entity(true)
      private = policy_entity(false)
      container = DB.create!(PolicyModule3.new())

      add_relationship(PolicyModule3, container.id, :children, public.id)
      add_relationship(PolicyModule3, container.id, :children, private.id)

      {[row], _applied_seq} = read(PolicyModule3, nil, nil, [PolicyModule1, PolicyModule3])

      assert sorted_ids(row.children) == [public.id]
    end

    test "includes an inverse of a to-many with only the targets the user may read" do
      seen = message("seen")
      hidden = message("hidden")
      tag = label("tag")

      add_relationship(Module28, seen.id, :labels, tag.id)
      add_relationship(Module28, hidden.id, :labels, tag.id)

      {[row], _applied_seq} = read(Module29, nil, nil, [Module28, Module29])

      assert sorted_ids(row.messages) == [seen.id]
    end

    test "answers the highest sequence number the replica has had confirmed" do
      confirmed(@replica_id, 1)
      confirmed(@replica_id, 2)

      assert read(Module2, nil, @replica_id, [Module2]) == {[], 2}
    end

    test "answers no number for a replica with no confirmed batch" do
      assert read(Module2, nil, @replica_id, [Module2]) == {[], nil}
    end

    test "answers no number for no replica" do
      confirmed(@replica_id, 1)

      assert read(Module2, nil, nil, [Module2]) == {[], nil}
    end
  end

  describe "read_ids/2" do
    test "answers the ids of the rows of the type the user may read" do
      user = policy_user("fill_ids@example.com")
      public = policy_entity(true)
      granted = policy_entity(false)
      policy_entity(false)

      Auth.grant_role(user, :viewer, granted)

      assert read_ids(PolicyModule1, user.id) == PackedIds.pack([public.id, granted.id])
    end

    test "reads a visitor through the read rules" do
      public = policy_entity(true)
      policy_entity(false)

      assert read_ids(PolicyModule1, nil) == PackedIds.pack([public.id])
    end

    test "answers nothing packed when the user may read no row of the type" do
      policy_entity(false)

      assert read_ids(PolicyModule1, nil) == ""
    end
  end

  describe "read_named/4" do
    test "answers the rows with the given ids the user may read" do
      named = policy_entity(true)
      hidden = policy_entity(false)
      policy_entity(true)

      {rows, nil} =
        read_named(%{PolicyModule1 => [named.id, hidden.id]}, nil, nil, [PolicyModule1])

      assert sorted_ids(rows) == [named.id]
    end

    test "reads the rows of every given type" do
      entity = policy_entity(true)
      tag = label("tag")

      {rows, nil} =
        read_named(
          %{Module29 => [tag.id], PolicyModule1 => [entity.id]},
          nil,
          nil,
          [Module29, PolicyModule1]
        )

      assert sorted_ids(rows) == Enum.sort([entity.id, tag.id])
    end

    test "reads a row with its sets" do
      child = policy_entity(true)
      container = DB.create!(PolicyModule3.new())

      add_relationship(PolicyModule3, container.id, :children, child.id)

      {[row], nil} =
        read_named(%{PolicyModule3 => [container.id]}, nil, nil, [PolicyModule1, PolicyModule3])

      assert sorted_ids(row.children) == [child.id]
    end

    test "answers the highest sequence number the replica has had confirmed" do
      confirmed(@replica_id, 3)

      assert read_named(%{}, nil, @replica_id, [Module2]) == {[], 3}
    end
  end

  describe "term/2" do
    test "includes every to-many relationship whose target is synced" do
      assert term(Module28, [Module26, Module28, Module29]) ==
               Module28
               |> Stage.normalize()
               |> Stage.include(:labels)
    end

    test "includes every inverse of a to-many whose target is synced" do
      assert term(Module29, [Module28, Module29]) ==
               Module29
               |> Stage.normalize()
               |> Stage.include(:messages)
    end

    # The reference fields of the related rows already say which row each belongs to.
    test "includes neither a to-one nor an inverse of a to-one" do
      assert term(Module26, [Module26, Module27, Module28]) == Stage.normalize(Module26)
    end

    test "leaves out a set whose target is not synced" do
      assert term(Module28, [Module26, Module28]) == Stage.normalize(Module28)
    end

    test "leaves out an inverse of a to-many whose target is not synced" do
      assert term(Module29, [Module29]) == Stage.normalize(Module29)
    end
  end
end
