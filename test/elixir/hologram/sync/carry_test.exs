defmodule Hologram.Sync.CarryTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Sync.Carry

  alias Hologram.Entity
  alias Hologram.Entity.NotIncluded
  alias Hologram.Entity.ServerOnly
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3

  @module_2_type "Hologram.Test.Fixtures.Entity.Module2"
  @module_3_type "Hologram.Test.Fixtures.Entity.Module3"

  setup do
    on_exit(fn ->
      take()
      take_counts()
      take_grant_scopes()
    end)

    :ok
  end

  defp module_2(overrides \\ []) do
    Entity.new(Module2, Keyword.merge([a: true, c: "a task"], overrides))
  end

  # A query result carries its includes in the relationship fields, which construction refuses
  # to set - the runner fills them when it decodes what the query embedded.
  defp module_3(embeds) do
    Module3
    |> Entity.new(c_id: Entity.generate_id())
    |> Map.merge(embeds)
  end

  describe "collect/1" do
    test "records the rows a result holds" do
      first = module_2(c: "first")
      second = module_2(c: "second")

      collect([first, second])

      assert %{put_entity: %{@module_2_type => rows}} = take()
      titles = Enum.map(rows, & &1.c)

      assert Enum.sort(titles) == ["first", "second"]
    end

    test "records the row of a single-result query" do
      collect(module_2(c: "the only one"))

      assert %{put_entity: %{@module_2_type => [row]}} = take()
      assert row.c == "the only one"
    end

    test "records nothing for a query matching no row" do
      collect(nil)

      assert take() == %{}
    end

    # A count holds no row - what the client needs of one is the number, which travels its own
    # way rather than as an entity that is not there.
    test "records nothing for a counting query" do
      collect(7)

      assert take() == %{}
    end

    test "records what a result embeds, and the row embedding it" do
      target = module_2(c: "embedded")
      source = module_3(%{a: [target]})

      collect([source])

      carried = take()

      assert %{@module_2_type => [embedded], @module_3_type => [row]} = carried.put_entity
      assert embedded.c == "embedded"
      assert row.id == source.id
    end

    test "records what an embedded row embeds, however deep" do
      deep = module_2(c: "two levels down")
      middle = module_3(%{a: [deep]})
      outer = module_3(%{b: middle, b_id: middle.id})

      collect([outer])

      carried = take()

      assert Enum.map(carried.put_entity[@module_2_type], & &1.c) == ["two levels down"]
      assert length(carried.put_entity[@module_3_type]) == 2
    end

    test "records a row reached through several results once" do
      target = module_2(c: "reached twice")
      first = module_3(%{a: [target]})
      second = module_3(%{a: [target]})

      collect([first, second])

      carried = take()

      assert length(carried.put_entity[@module_2_type]) == 1
      assert length(carried.put_entity[@module_3_type]) == 2
    end

    test "gathers the rows of every result collected" do
      collect([module_2(c: "from the first prop")])
      collect([module_2(c: "from the second prop")])

      assert %{put_entity: %{@module_2_type => rows}} = take()

      assert rows
             |> Enum.map(& &1.c)
             |> Enum.sort() == ["from the first prop", "from the second prop"]
    end

    test "passes over a relationship the query did not ask for" do
      collect([module_3(%{a: %NotIncluded{relationship: :a}})])

      assert %{put_entity: %{@module_3_type => [_row]}} = take()
    end

    # Rows travel the way a frame spells them: flat, with a to-many naming the ids it holds
    # rather than carrying the rows, which travel as rows of their own.
    test "spells a row the way a frame spells it" do
      target = module_2(c: "the target")
      source = module_3(%{a: [target]})

      collect([source])

      %{put_entity: %{@module_3_type => [row]}} = take()

      assert row.a == [target.id]
      refute Map.has_key?(row, :b)
    end

    test "never spells a value the client may not have" do
      user =
        Entity.new(Module14,
          email: "user@test.com",
          password_hash: %ServerOnly{attribute: :password_hash}
        )

      collect([user])

      carried = take()
      [row] = carried.put_entity["Hologram.Test.Fixtures.Entity.Module14"]

      assert row.email == "user@test.com"
      refute Map.has_key?(row, :password_hash)
    end

    test "gathers rows of every type a page's props read" do
      collect([module_2(c: "a task")])
      collect([Entity.new(Module1)])

      carried = take()

      assert Map.keys(carried.put_entity) == [
               "Hologram.Test.Fixtures.Entity.Module1",
               @module_2_type
             ]
    end
  end

  describe "collect_count/4" do
    test "records a count under the prop that answered it" do
      collect_count(Module2, :total, [], 7)

      assert take_counts() == %{"Hologram.Test.Fixtures.Entity.Module2/total/" => 7}
    end

    # Two instances of one component answer two counts, and what tells them apart is what their
    # builders were called with.
    test "keys instances apart by the arguments the builder was called with" do
      collect_count(Module2, :total, ["p1"], 7)
      collect_count(Module2, :total, ["p2"], 3)

      assert take_counts() == %{
               ~s(Hologram.Test.Fixtures.Entity.Module2/total/"p1") => 7,
               ~s(Hologram.Test.Fixtures.Entity.Module2/total/"p2") => 3
             }
    end

    test "spells every argument of a multi-argument builder" do
      collect_count(Module2, :total, ["p1", true], 7)

      assert take_counts() == %{~s(Hologram.Test.Fixtures.Entity.Module2/total/"p1",true) => 7}
    end

    test "keys props of one component apart" do
      collect_count(Module2, :open_total, [], 7)
      collect_count(Module2, :done_total, [], 3)

      assert take_counts() == %{
               "Hologram.Test.Fixtures.Entity.Module2/open_total/" => 7,
               "Hologram.Test.Fixtures.Entity.Module2/done_total/" => 3
             }
    end

    # The same prop of the same instance resolved twice is one answer, not two - the later one,
    # which is what a re-render would have produced.
    test "records one count per prop instance" do
      collect_count(Module2, :total, ["p1"], 7)
      collect_count(Module2, :total, ["p1"], 9)

      assert take_counts() == %{~s(Hologram.Test.Fixtures.Entity.Module2/total/"p1") => 9}
    end
  end

  describe "record_grant_scope/2" do
    test "records the question a permission check asked" do
      start()

      record_grant_scope("user-1", {:own, Module2, "row-1"})

      assert take_grant_scopes() == MapSet.new([{"user-1", {:own, Module2, "row-1"}}])
    end

    test "records one entry for a question asked twice" do
      start()

      record_grant_scope("user-1", {:own, Module2, "row-1"})
      record_grant_scope("user-1", {:own, Module2, "row-1"})

      assert MapSet.size(take_grant_scopes()) == 1
    end

    test "keeps questions about different users apart" do
      start()

      record_grant_scope("user-1", :global)
      record_grant_scope("user-2", :global)

      assert MapSet.size(take_grant_scopes()) == 2
    end

    # A permission check outside a render - a command handler, a mix task, an IEx session - finds
    # no collector armed and records nothing, so the trusted paths pay none of this.
    test "records nothing when no render is gathering" do
      take_grant_scopes()

      record_grant_scope("user-1", :global)

      assert take_grant_scopes() == MapSet.new()
    end
  end

  describe "start/0" do
    test "clears the counts a previous render gathered" do
      collect_count(Module2, :total, [], 7)

      start()

      assert take_counts() == %{}
    end

    test "arms the grant-scope recorder" do
      take_grant_scopes()
      start()

      record_grant_scope("user-1", :global)

      assert MapSet.size(take_grant_scopes()) == 1
    end

    test "clears the questions a previous render asked" do
      start()
      record_grant_scope("user-1", :global)

      start()

      assert take_grant_scopes() == MapSet.new()
    end
  end

  describe "take/0" do
    test "returns nothing when no result was collected" do
      assert take() == %{}
    end

    # What a render gathered belongs to that render: a second page rendered in the same process
    # would otherwise be seeded with the first one's rows.
    test "leaves nothing behind for the next render" do
      collect([module_2()])

      take()

      assert take() == %{}
    end
  end

  describe "take_grant_scopes/0" do
    test "returns nothing when no question was asked" do
      assert take_grant_scopes() == MapSet.new()
    end

    test "leaves nothing behind for the next render" do
      start()
      record_grant_scope("user-1", :global)

      take_grant_scopes()

      assert take_grant_scopes() == MapSet.new()
    end
  end

  describe "take_counts/0" do
    test "returns nothing when no count was collected" do
      assert take_counts() == %{}
    end

    test "leaves nothing behind for the next render" do
      collect_count(Module2, :total, [], 7)

      take_counts()

      assert take_counts() == %{}
    end
  end
end
