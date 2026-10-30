defmodule Hologram.Sync.ScoperTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Sync.Scoper

  alias Hologram.Auth.RoleGrant
  alias Hologram.Policy.Edges
  alias Hologram.Query
  alias Hologram.Query.Stage
  alias Hologram.Query.Window
  alias Hologram.Reflection
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1
  alias Hologram.Test.Fixtures.Policy.Module12, as: PolicyModule12
  alias Hologram.Test.Fixtures.Policy.Module2, as: PolicyModule2
  alias Hologram.Test.Fixtures.Policy.Module5, as: PolicyModule5

  defp events(entity_types) do
    events = Enum.map(entity_types, &%{op: :patch_entity, type: &1})

    [{200, events}]
  end

  defp term(entity_type, include \\ %{}) do
    %Query{entity: entity_type, include: include}
  end

  describe "affected/3" do
    test "returns no keys when nothing was written" do
      windows = [{:board, term(Module2)}]

      assert affected([], windows, %{}) == []
    end

    test "includes a window whose query reads the type that changed" do
      windows = [{:board, term(Module2)}]

      assert affected(events([Module2]), windows, %{}) == [:board]
    end

    test "leaves out a window whose query reads nothing that changed" do
      windows = [{:board, term(Module2)}]

      assert affected(events([Module3]), windows, %{}) == []
    end

    test "includes a window whose query reaches the changed type through an include" do
      windows = [{:board, term(Module3, %{a: term(Module2)})}]

      assert affected(events([Module2]), windows, %{}) == [:board]
    end

    test "includes a window reaching the changed type through a nested include" do
      windows = [{:board, term(Module3, %{a: term(Module3, %{a: term(Module2)})})}]

      assert affected(events([Module2]), windows, %{}) == [:board]
    end

    test "includes a window whose query reads the changed type through a path" do
      window = %{term(Module3, %{b: term(Module2)}) | filter: [{[:b, :a], :==, true}]}

      assert affected(events([Module2]), [{:board, window}], %{}) == [:board]
    end

    test "returns every window a transaction reached, and only those" do
      windows = [
        {:board, term(Module2)},
        {:other, term(Module3)},
        {:profile, term(Module14)}
      ]

      assert affected(events([Module2, Module14]), windows, %{}) == [:board, :profile]
    end

    test "includes the windows of every transaction in the batch" do
      transactions = [
        {200, [%{op: :patch_entity, type: Module2}]},
        {201, [%{op: :del_entity, type: Module14}]}
      ]

      windows = [{:board, term(Module2)}, {:profile, term(Module14)}]

      assert affected(transactions, windows, %{}) == [:board, :profile]
    end

    test "includes a window whose policy grants by role when a grant changes" do
      edges = Edges.derive(Reflection.list_entities())
      windows = [{:board, term(PolicyModule1)}]

      assert affected(events([RoleGrant]), windows, edges) == [:board]
    end

    test "leaves out a window whose policy reads only its own attributes when a grant changes" do
      edges = Edges.derive(Reflection.list_entities())
      windows = [{:profile, term(Module14)}]

      assert affected(events([RoleGrant]), windows, edges) == []
    end

    test "includes a window reading a type whose grants are held on another type" do
      edges = Edges.derive(Reflection.list_entities())
      windows = [{:board, term(PolicyModule2)}]

      assert affected(events([RoleGrant]), windows, edges) == [:board]
    end

    test "includes a window whose policy reads a related row's attributes when that type changes" do
      edges = %{
        {Module2, :read} => [{:relationship_attributes, [:parent], PolicyModule1, [:public]}]
      }

      windows = [{:board, term(Module2)}]

      assert affected(events([PolicyModule1]), windows, edges) == [:board]
    end

    # The row in between holds the reference the path is followed through, so a change to it can
    # move where the path ends.
    test "includes a window whose policy reads an intermediate row of a path when that type changes" do
      edges =
        [PolicyModule12]
        |> Edges.derive()
        |> Map.take([{PolicyModule12, :read}])

      windows = [{:board, term(PolicyModule12)}]

      assert affected(events([PolicyModule5]), windows, edges) == [:board]
    end

    # No read rule of the type reads its parent's row - its publish rule does, by delegating to it -
    # so the read edges name nothing of the parent type. The window downloads the parent for a client
    # checking permissions, and a change to it reaches the window the way a change to any row it
    # includes does.
    test "includes a window embedding the rows a rule of another operation reads when their type changes" do
      edges = Edges.derive(Reflection.list_entities())

      window =
        PolicyModule1
        |> Stage.normalize()
        |> Window.derive(true)

      assert affected(events([PolicyModule2]), [{:board, window}], edges) == [:board]
    end

    test "leaves out a window of a build no client checks permissions in when such a type changes" do
      edges = Edges.derive(Reflection.list_entities())

      window =
        PolicyModule1
        |> Stage.normalize()
        |> Window.derive(false)

      assert affected(events([PolicyModule2]), [{:board, window}], edges) == []
    end

    test "ignores an entity type this node has never compiled" do
      windows = [{:board, term(Module2)}]

      assert affected(events(["MyApp.TypeOnlyThisTestNames"]), windows, %{}) == []
    end
  end
end
