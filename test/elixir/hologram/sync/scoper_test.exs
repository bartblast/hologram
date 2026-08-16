defmodule Hologram.Sync.ScoperTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Sync.Scoper

  alias Hologram.Auth.RoleGrant
  alias Hologram.Policy.Edges
  alias Hologram.Reflection
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1
  alias Hologram.Test.Fixtures.Policy.Module2, as: PolicyModule2

  defp events(entity_types) do
    events = Enum.map(entity_types, &%{op: :patch_entity, type: &1})

    [{200, events}]
  end

  defp term(entity_type, include \\ %{}) do
    %{entity: entity_type, filter: [], include: include, order_by: []}
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

    test "ignores an entity type this node has never compiled" do
      windows = [{:board, term(Module2)}]

      assert affected(events(["MyApp.TypeOnlyThisTestNames"]), windows, %{}) == []
    end
  end
end
