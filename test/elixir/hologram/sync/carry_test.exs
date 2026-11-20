defmodule Hologram.Sync.CarryTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Sync.Carry
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Entity
  alias Hologram.Entity.NotIncluded
  alias Hologram.Entity.ServerOnly
  alias Hologram.Policy
  alias Hologram.Query.Stage
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module10
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module17
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module22
  alias Hologram.Test.Fixtures.Entity.Module26
  alias Hologram.Test.Fixtures.Entity.Module27
  alias Hologram.Test.Fixtures.Entity.Module28
  alias Hologram.Test.Fixtures.Entity.Module29
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module38

  @module_2_type "Hologram.Test.Fixtures.Entity.Module2"
  @module_3_type "Hologram.Test.Fixtures.Entity.Module3"

  use_module_stub :query_cache

  # A task may be deleted while its board holds no card by the user - read through the task's
  # board, so a task with no board has an empty set, answered without reading the database: yes for
  # a user, and no for a visitor, since the rule asks about the actor.
  defmodule VerdictBoard do
    use Hologram.Entity

    relationship :cards, [__MODULE__.Card], inverse: board

    allow :read

    defmodule Card do
      use Hologram.Entity

      relationship :author, Hologram.Test.Fixtures.Entity.Module14, optional: true
      relationship :board, Hologram.Sync.CarryTest.VerdictBoard, optional: true

      allow :read
    end
  end

  defmodule VerdictTask do
    use Hologram.Entity

    relationship :board, VerdictBoard, optional: true

    allow :read
    allow :delete, when: none(card <- board.cards, card.author_id == user_id())
  end

  defp delete_key do
    Policy.verdict_key(VerdictTask, :delete)
  end

  # A build with a page checking permissions on the client - the only kind whose rows carry
  # verdicts.
  defp check_permissions do
    stub_with(QueryCacheMock, QueryCacheStub)
    :persistent_term.put(QueryCacheStub.persistent_term_key(), %{permission_checking?: true})

    on_exit(fn -> :persistent_term.erase(QueryCacheStub.persistent_term_key()) end)
  end

  setup do
    on_exit(fn ->
      take(nil)
      take_counts()
      take_grant_scopes()
    end)

    :ok
  end

  defp module_2(overrides \\ []) do
    [a: true, c: "a task"]
    |> Keyword.merge(overrides)
    |> Module2.new()
  end

  # A query result carries its includes in the relationship fields, which construction refuses
  # to set - the runner fills them when it decodes what the query embedded.
  defp module_3(embeds) do
    %{c_id: Entity.generate_id()}
    |> Module3.new()
    |> Map.merge(embeds)
  end

  defp c_count_term(value) do
    Module2
    |> Stage.filter(c: value)
    |> Stage.count()
    |> Stage.normalize()
  end

  defp count_key(name, term), do: "#{inspect(Module2)}/#{name}/#{spell_query(term)}"

  defp spell(query) do
    query
    |> Stage.normalize()
    |> spell_query()
  end

  defp total_term do
    Module2
    |> Stage.count()
    |> Stage.normalize()
  end

  describe "collect/1" do
    test "records the rows a result holds" do
      first = module_2(c: "first")
      second = module_2(c: "second")

      collect([first, second])

      assert %{put_entity: %{@module_2_type => rows}} = take(nil)
      titles = Enum.map(rows, & &1.c)

      assert Enum.sort(titles) == ["first", "second"]
    end

    test "records the row of a single-result query" do
      collect(module_2(c: "the only one"))

      assert %{put_entity: %{@module_2_type => [row]}} = take(nil)
      assert row.c == "the only one"
    end

    test "records nothing for a query matching no row" do
      collect(nil)

      assert take(nil) == %{}
    end

    # A count holds no row - what the client needs of one is the number, which travels its own
    # way rather than as an entity that is not there.
    test "records nothing for a counting query" do
      collect(7)

      assert take(nil) == %{}
    end

    test "records what a result embeds, and the row embedding it" do
      target = module_2(c: "embedded")
      source = module_3(%{a: [target]})

      collect([source])

      carried = take(nil)

      assert %{@module_2_type => [embedded], @module_3_type => [row]} = carried.put_entity
      assert embedded.c == "embedded"
      assert row.id == source.id
    end

    test "records what an embedded row embeds, however deep" do
      deep = module_2(c: "two levels down")
      middle = module_3(%{a: [deep]})
      outer = module_3(%{b: middle, b_id: middle.id})

      collect([outer])

      carried = take(nil)

      assert Enum.map(carried.put_entity[@module_2_type], & &1.c) == ["two levels down"]
      assert length(carried.put_entity[@module_3_type]) == 2
    end

    test "records a row reached through several results once" do
      target = module_2(c: "reached twice")
      first = module_3(%{a: [target]})
      second = module_3(%{a: [target]})

      collect([first, second])

      carried = take(nil)

      assert length(carried.put_entity[@module_2_type]) == 1
      assert length(carried.put_entity[@module_3_type]) == 2
    end

    # The second label is met first as the message's, where its own messages are not included -
    # its root copy, holding them, comes after.
    test "records a row reached several times with what each copy included" do
      message = struct(Module28, %{body: "tagged", id: Entity.generate_id()})
      first_label = struct(Module29, %{id: Entity.generate_id(), name: "first"})
      second_label = struct(Module29, %{id: Entity.generate_id(), name: "second"})

      tagged = %{message | labels: [first_label, second_label]}

      collect([%{first_label | messages: [tagged]}, %{second_label | messages: [message]}])

      carried = take(nil)

      assert carried.put_entity["Hologram.Test.Fixtures.Entity.Module29"]
             |> Enum.find(&(&1.id == second_label.id))
             |> Map.fetch!(:messages) == [message.id]
    end

    # The same shape without an inverse: a folder met first as another folder's child, where its
    # own children are not included, still carries them.
    test "records a row a to-many of its own type reaches with what each copy included" do
      defmodule FolderEntityFixture do
        use Hologram.Entity

        attribute :name, :string

        relationship :children, [__MODULE__]

        allow :read
      end

      child = FolderEntityFixture.new(%{name: "child"})
      grandchild = FolderEntityFixture.new(%{name: "grandchild"})
      parent = FolderEntityFixture.new(%{name: "parent"})

      collect([%{parent | children: [child]}, %{child | children: [grandchild]}])

      carried = take(nil)

      assert carried.put_entity[inspect(FolderEntityFixture)]
             |> Enum.find(&(&1.id == child.id))
             |> Map.fetch!(:children) == [grandchild.id]
    end

    test "gathers the rows of every result collected" do
      collect([module_2(c: "from the first prop")])
      collect([module_2(c: "from the second prop")])

      assert %{put_entity: %{@module_2_type => rows}} = take(nil)

      assert rows
             |> Enum.map(& &1.c)
             |> Enum.sort() == ["from the first prop", "from the second prop"]
    end

    test "records the rows an included inverse holds" do
      channel = struct(Module26, %{id: Entity.generate_id(), name: "general"})
      message = struct(Module28, %{body: "hi", channel_id: channel.id, id: Entity.generate_id()})
      topic = struct(Module27, %{channel_id: channel.id, id: Entity.generate_id()})

      collect([%{channel | messages: [message], topic: topic}])

      carried = take(nil)

      assert [%{body: "hi"}] = carried.put_entity["Hologram.Test.Fixtures.Entity.Module28"]
      assert [%{id: topic_id}] = carried.put_entity["Hologram.Test.Fixtures.Entity.Module27"]
      assert topic_id == topic.id
    end

    test "passes over a relationship the query did not ask for" do
      collect([module_3(%{a: %NotIncluded{relationship: :a}})])

      assert %{put_entity: %{@module_3_type => [_row]}} = take(nil)
    end

    # Rows travel the way a frame spells them: flat, with a to-many naming the ids it holds
    # rather than carrying the rows, which travel as rows of their own.
    test "spells a row the way a frame spells it" do
      target = module_2(c: "the target")
      source = module_3(%{a: [target]})

      collect([source])

      %{put_entity: %{@module_3_type => [row]}} = take(nil)

      assert row.a == [target.id]
      refute Map.has_key?(row, :b)
    end

    test "never spells a value the client may not have" do
      user =
        Module14.new(
          email: "user@test.com",
          password_hash: %ServerOnly{attribute: :password_hash}
        )

      collect([user])

      carried = take(nil)
      [row] = carried.put_entity["Hologram.Test.Fixtures.Entity.Module14"]

      assert row.email == "user@test.com"
      refute Map.has_key?(row, :password_hash)
    end

    test "gathers rows of every type a page's props read" do
      collect([module_2(c: "a task")])
      collect([Module1.new()])

      carried = take(nil)

      assert Map.keys(carried.put_entity) == [
               "Hologram.Test.Fixtures.Entity.Module1",
               @module_2_type
             ]
    end
  end

  describe "collect_count/4" do
    test "records a count under the field and the query that answered it" do
      collect_count(Module2, :total, total_term(), 7)

      assert take_counts() == %{
               ~S|Hologram.Test.Fixtures.Entity.Module2/total/{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[],"include":{},"skip":null,"sort":[],"take":null}| =>
                 7
             }
    end

    # Two instances of one component answer two counts, and what tells them apart is the query
    # each one's builder built.
    test "keys instances apart by the query their builders built" do
      collect_count(Module2, :total, c_count_term("p1"), 7)
      collect_count(Module2, :total, c_count_term("p2"), 3)

      assert take_counts() == %{
               ~S|Hologram.Test.Fixtures.Entity.Module2/total/{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[["c","==","p1"]],"include":{},"skip":null,"sort":[],"take":null}| =>
                 7,
               ~S|Hologram.Test.Fixtures.Entity.Module2/total/{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[["c","==","p2"]],"include":{},"skip":null,"sort":[],"take":null}| =>
                 3
             }
    end

    test "keys fields of one component apart" do
      collect_count(Module2, :open_total, total_term(), 7)
      collect_count(Module2, :done_total, total_term(), 3)

      assert take_counts() == %{
               count_key(:open_total, total_term()) => 7,
               count_key(:done_total, total_term()) => 3
             }
    end

    test "records the entity types the count reads under the count's key" do
      term =
        Module3
        |> Stage.filter([{[:c, :id], {:!=, nil}}])
        |> Stage.count()
        |> Stage.normalize()

      collect_count(Module2, :total, term, 7)

      assert take_count_types() == %{
               count_key(:total, term) => [inspect(Module1), inspect(Module3)]
             }
    end

    # The same field running the same query twice is one answer, not two - the later one, which is
    # what a re-render would have produced.
    test "records one count per field and query" do
      collect_count(Module2, :total, c_count_term("p1"), 7)
      collect_count(Module2, :total, c_count_term("p1"), 9)

      assert take_counts() == %{count_key(:total, c_count_term("p1")) => 9}
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

  # Each spelling here built through the stages is asserted letter for letter in the client's suite
  # too (test/javascript/query_spelling_test.mjs), over the same query built by the client's stages:
  # the two tiers agreeing is what lets a page's carried answer be found by its query. The terms
  # changed by hand after normalizing are server-only - shapes the client's stages never build.
  describe "spell_query/1" do
    test "spells a count with no filter" do
      assert spell(Stage.count(Module2)) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[],"include":{},"skip":null,"sort":[],"take":null}|
    end

    # A boolean is spelled as text, the way the client holds an enum declaring true.
    test "spells a boolean as text and nil as null" do
      query =
        Module2
        |> Stage.filter(a: true, b: nil)
        |> Stage.count()

      assert spell(query) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[["a","==","true"],["b","==",null]],"include":{},"skip":null,"sort":[],"take":null}|
    end

    test "spells a string with its quotes and backslashes escaped and the rest as it is" do
      query =
        Module2
        |> Stage.filter(c: ~S|say "hi" \ żółw|)
        |> Stage.count()

      assert spell(query) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[["c","==","say \"hi\" \\ żółw"]],"include":{},"skip":null,"sort":[],"take":null}|
    end

    test "spells an integer, a float, a date and a datetime as the client holds them" do
      query =
        Module10
        |> Stage.filter(
          count: 3,
          rating: 2.5,
          released_on: ~D[2026-01-02],
          held_at: ~U[2026-01-02 03:04:05.12Z]
        )
        |> Stage.count()

      assert spell(query) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module10","filter":[["count","==",3],["held_at","==","2026-01-02T03:04:05.120000Z"],["rating","==",float:4004000000000000],["released_on","==","2026-01-02"]],"include":{},"skip":null,"sort":[],"take":null}|
    end

    # A datetime outside UTC is spelled as the UTC instant it stands for, and a year below 0 with
    # its minus ahead of the padding - which the client spells alike only once it moves the clock
    # and signs the year itself. Built by hand, since the suite has no time zone database.
    test "spells a datetime outside UTC as its instant, and a year below 0 or above 9999 as Date.to_iso8601/1 does" do
      warsaw_midnight = %DateTime{
        year: 2026,
        month: 3,
        day: 1,
        hour: 0,
        minute: 0,
        second: 0,
        microsecond: {0, 0},
        std_offset: 0,
        time_zone: "Europe/Warsaw",
        utc_offset: 3600,
        zone_abbr: "CET"
      }

      query =
        Module10
        |> Stage.filter(
          held_at: warsaw_midnight,
          released_on: {:>=, ~D[-0001-01-02]},
          released_on: {:<, Date.new!(20_250, 1, 2)}
        )
        |> Stage.count()

      assert spell(query) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module10","filter":[["held_at","==","2026-02-28T23:00:00.000000Z"],["released_on","<","20250-01-02"],["released_on",">=","-0001-01-02"]],"include":{},"skip":null,"sort":[],"take":null}|
    end

    # The client holds 2.0 and 2 as one Number, so the two have to spell alike.
    test "spells a whole float as an integer" do
      query =
        Module10
        |> Stage.filter(rating: {:>=, 2.0})
        |> Stage.count()

      assert spell(query) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module10","filter":[["rating",">=",2]],"include":{},"skip":null,"sort":[],"take":null}|
    end

    test "spells an enum value as the client holds it" do
      query =
        Module17
        |> Stage.filter(priority: :high)
        |> Stage.count()

      assert spell(query) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module17","filter":[["priority","==","high"]],"include":{},"skip":null,"sort":[],"take":null}|
    end

    test "spells a time at full precision" do
      query =
        Module22
        |> Stage.filter(opens_at: ~T[09:30:00])
        |> Stage.count()

      assert spell(query) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module22","filter":[["opens_at","==","09:30:00.000000"]],"include":{},"skip":null,"sort":[],"take":null}|
    end

    test "spells a reference as its id" do
      query =
        Module28
        |> Stage.filter(channel_id: "0190e4c1-0000-7000-8000-000000000001")
        |> Stage.count()

      assert spell(query) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module28","filter":[["channel_id","==","0190e4c1-0000-7000-8000-000000000001"]],"include":{},"skip":null,"sort":[],"take":null}|
    end

    # The clauses are sorted by their spelling rather than kept in the normalizer's order, which the
    # client's normalizer doesn't share.
    test "spells one filter written in two orders alike" do
      one_order =
        Module2
        |> Stage.filter(a: true, c: "x")
        |> Stage.count()

      other_order =
        Module2
        |> Stage.filter(c: "x", a: true)
        |> Stage.count()

      assert spell(one_order) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[["a","==","true"],["c","==","x"]],"include":{},"skip":null,"sort":[],"take":null}|

      assert spell(other_order) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[["a","==","true"],["c","==","x"]],"include":{},"skip":null,"sort":[],"take":null}|
    end

    # A membership list keeps the order it was written in, as both normalizers keep it.
    test "spells a membership list and a range" do
      query =
        Module2
        |> Stage.filter(c: ["y", "x"], b: 1..3)
        |> Stage.count()

      assert spell(query) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[["b","<=",3],["b",">=",1],["c","in",["y","x"]]],"include":{},"skip":null,"sort":[],"take":null}|
    end

    # The normalizer orders 9 before 10, and the spelling orders "10" before "9".
    test "sorts a disjunction's alternatives by their spelling" do
      query =
        Module28
        |> Stage.filter(or: [[position: 9], [position: 10]])
        |> Stage.count()

      assert spell(query) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module28","filter":[{"or":[[["position","==",10]],[["position","==",9]]]}],"include":{},"skip":null,"sort":[],"take":null}|
    end

    test "spells a path" do
      query =
        Module28
        |> Stage.filter([{[:channel, :name], "general"}])
        |> Stage.count()

      assert spell(query) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module28","filter":[[["channel","name"],"==","general"]],"include":{},"skip":null,"sort":[],"take":null}|
    end

    test "spells an attribute compared with another" do
      query =
        Module28
        |> Stage.filter(body: {:attribute, [:channel, :name]})
        |> Stage.count()

      assert spell(query) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module28","filter":[["body","==",{"attribute":["channel","name"]}]],"include":{},"skip":null,"sort":[],"take":null}|
    end

    test "spells a quantifier reading the row one level out" do
      query =
        Module28
        |> Stage.filter(any: {[:labels], [name: {:attribute, {:outer, 1, :body}}]})
        |> Stage.count()

      assert spell(query) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module28","filter":[{"filter":[["name","==",{"attribute":{"name":"body","outer":1}}]],"quantifier":"any","source":["labels"]}],"include":{},"skip":null,"sort":[],"take":null}|
    end

    test "spells an include and the view bounds" do
      query =
        Module28
        |> Stage.include(:labels)
        |> Stage.take(5)
        |> Stage.skip(2)

      assert spell(query) ==
               ~S|{"cardinality":"set","entity":"Hologram.Test.Fixtures.Entity.Module28","filter":[],"include":{"labels":{"cardinality":"set","entity":"Hologram.Test.Fixtures.Entity.Module29","filter":[],"include":{},"skip":null,"sort":[["id","asc"]],"take":null}},"skip":2,"sort":[["id","asc"]],"take":5}|
    end

    test "spells an include in the order its relationship declares" do
      query =
        Module26
        |> Stage.include(:messages)
        |> Stage.count()

      assert spell(query) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module26","filter":[],"include":{"messages":{"cardinality":"set","entity":"Hologram.Test.Fixtures.Entity.Module28","filter":[],"include":{},"skip":null,"sort":[["position","asc"],["id","asc"]],"take":null}},"skip":null,"sort":[],"take":null}|
    end

    test "spells a sort" do
      assert spell(Stage.sort(Module2, :c)) ==
               ~S|{"cardinality":"set","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[],"include":{},"skip":null,"sort":[["c","asc"],["id","asc"]],"take":null}|
    end

    # The normalizer orders 9 before 10, and the spelling orders "10" before "9".
    test "sorts clauses by their spelling rather than as the normalizer does" do
      query =
        Module2
        |> Stage.filter(b: [{:!=, 10}, {:!=, 9}])
        |> Stage.count()

      assert spell(query) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[["b","!=",10],["b","!=",9]],"include":{},"skip":null,"sort":[],"take":null}|
    end

    # The normalizer orders a disjunction before a predicate, and the spelling the other way round.
    test "sorts a disjunction among the clauses by its spelling" do
      query =
        Module28
        |> Stage.filter(position: 1, or: [[body: "a"], [body: "b"]])
        |> Stage.count()

      assert spell(query) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module28","filter":[["position","==",1],{"or":[[["body","==","a"]],[["body","==","b"]]]}],"include":{},"skip":null,"sort":[],"take":null}|
    end

    test "sorts the clauses of a disjunction's alternative by their spelling" do
      query =
        Module28
        |> Stage.filter(or: [[position: {:!=, 10}, position: {:!=, 9}], [body: "b"]])
        |> Stage.count()

      assert spell(query) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module28","filter":[{"or":[[["body","==","b"]],[["position","!=",10],["position","!=",9]]]}],"include":{},"skip":null,"sort":[],"take":null}|
    end

    test "sorts the clauses of a quantifier's condition by their spelling" do
      query =
        Module28
        |> Stage.filter(any: {[:labels], [name: "x", or: [[name: "y"], [name: "z"]]]})
        |> Stage.count()

      assert spell(query) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module28","filter":[{"filter":[["name","==","x"],{"or":[[["name","==","y"]],[["name","==","z"]]]}],"quantifier":"any","source":["labels"]}],"include":{},"skip":null,"sort":[],"take":null}|
    end

    test "spells all over a set" do
      query =
        Module26
        |> Stage.filter(all: {[:messages], [position: {:>, 0}]})
        |> Stage.count()

      assert spell(query) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module26","filter":[{"filter":[["position",">",0]],"quantifier":"all","source":["messages"]}],"include":{},"skip":null,"sort":[],"take":null}|
    end

    test "spells none over a set and a source starting on the row one level out" do
      query =
        Module26
        |> Stage.filter(none: {[:messages], [any: {{:outer, 1, [:messages]}, [body: "x"]}]})
        |> Stage.count()

      assert spell(query) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module26","filter":[{"filter":[{"filter":[["body","==","x"]],"quantifier":"any","source":{"name":["messages"],"outer":1}}],"quantifier":"none","source":["messages"]}],"include":{},"skip":null,"sort":[],"take":null}|
    end

    test "spells a to-one include with no order and what it includes in turn" do
      query =
        Module28
        |> Stage.include(channel: :messages)
        |> Stage.count()

      assert spell(query) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module28","filter":[],"include":{"channel":{"cardinality":"set","entity":"Hologram.Test.Fixtures.Entity.Module26","filter":[],"include":{"messages":{"cardinality":"set","entity":"Hologram.Test.Fixtures.Entity.Module28","filter":[],"include":{},"skip":null,"sort":[["position","asc"],["id","asc"]],"take":null}},"skip":null,"sort":[],"take":null}},"skip":null,"sort":[],"take":null}|
    end

    test "spells an included derived value as null" do
      query =
        Module38
        |> Stage.include(:sibling_count)
        |> Stage.count()

      assert spell(query) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module38","filter":[],"include":{"sibling_count":null},"skip":null,"sort":[],"take":null}|
    end

    test "spells a query answering one row" do
      query =
        Module2
        |> Stage.filter(c: "x")
        |> Stage.one()

      assert spell(query) ==
               ~S|{"cardinality":"one","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[["c","==","x"]],"include":{},"skip":null,"sort":[["id","asc"]],"take":null}|
    end

    test "spells nil in a membership list as null" do
      query =
        Module2
        |> Stage.filter(c: ["x", nil])
        |> Stage.count()

      assert spell(query) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[["c","in",["x",null]]],"include":{},"skip":null,"sort":[],"take":null}|
    end

    # The client holds negative zero as a Number that prints as 0.
    test "spells a negative number with its sign and negative zero as 0" do
      query =
        Module10
        |> Stage.filter(count: {:>, -3}, rating: {:<, -0.0})
        |> Stage.count()

      assert spell(query) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module10","filter":[["count",">",-3],["rating","<",0]],"include":{},"skip":null,"sort":[],"take":null}|
    end

    # A float attribute takes an integer too, which the client holds as the same Number.
    test "spells an integer compared with a float attribute as the whole float would be" do
      query =
        Module10
        |> Stage.filter(rating: 2)
        |> Stage.count()

      assert spell(query) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module10","filter":[["rating","==",2]],"include":{},"skip":null,"sort":[],"take":null}|
    end

    test "spells a whole float past what a JavaScript Number holds exactly by its bits" do
      query =
        Module10
        |> Stage.filter(rating: 9_007_199_254_740_992.0)
        |> Stage.count()

      assert spell(query) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module10","filter":[["rating","==",float:4340000000000000]],"include":{},"skip":null,"sort":[],"take":null}|
    end

    # A character past U+FFFF is two code units in JavaScript, whose own comparison sorts it below
    # U+FFFD, where code point order puts it above.
    test "sorts clauses by code point" do
      query =
        Module2
        |> Stage.filter(c: "😀", c: "\u{FFFD}")
        |> Stage.count()

      assert spell(query) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[["c","==","| <>
                 "\u{FFFD}" <>
                 ~S|"],["c","==","😀"]],"include":{},"skip":null,"sort":[],"take":null}|
    end

    test "spells the largest whole float a JavaScript Number holds exactly as an integer" do
      query =
        Module10
        |> Stage.filter(rating: 9_007_199_254_740_991.0)
        |> Stage.count()

      assert spell(query) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module10","filter":[["rating","==",9007199254740991]],"include":{},"skip":null,"sort":[],"take":null}|
    end

    test "spells a negative fraction by its bits" do
      query =
        Module10
        |> Stage.filter(rating: {:<, -2.5})
        |> Stage.count()

      assert spell(query) ==
               ~S|{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module10","filter":[["rating","<",float:c004000000000000]],"include":{},"skip":null,"sort":[],"take":null}|
    end

    # What the client spells never starts with a question mark, so a shape this doesn't know can't
    # match a key the client builds.
    test "spells a value of a shape it doesn't know so that no client spelling matches it" do
      term = %{Stage.normalize(Module2) | filter: [{:c, :==, {:unknown}}]}

      assert spell_query(term) ==
               ~S|{"cardinality":"set","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[["c","==",?{:unknown}]],"include":{},"skip":null,"sort":[["id","asc"]],"take":null}|
    end

    # A client refuses trust, so no term it builds is trusted, and a carried answer that read past
    # the policies must not be found for one that didn't.
    test "spells a trusted term so that no client spelling matches it" do
      term = %{Stage.normalize(Module2) | trust: true}

      assert spell_query(term) ==
               "?" <> inspect(term, limit: :infinity, printable_limit: :infinity)
    end

    test "spells a term with a source so that no client spelling matches it" do
      term = %{Stage.normalize(Module2) | source: {Module26, [:messages]}}

      assert spell_query(term) ==
               "?" <> inspect(term, limit: :infinity, printable_limit: :infinity)
    end

    test "spells an include of a shape it doesn't know so that no client spelling matches it" do
      term = %{Stage.normalize(Module2) | include: %{1 => nil}}

      assert spell_query(term) ==
               ~S|{"cardinality":"set","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[],"include":?%{1 => nil},"skip":null,"sort":[["id","asc"]],"take":null}|
    end

    test "spells an integer past what a JavaScript Number holds exactly in full" do
      term = %{Stage.normalize(Module2) | filter: [{:b, :==, 9_007_199_254_740_993}]}

      assert spell_query(term) ==
               ~S|{"cardinality":"set","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[["b","==",9007199254740993]],"include":{},"skip":null,"sort":[["id","asc"]],"take":null}|
    end
  end

  describe "start/0" do
    test "clears the counts a previous render gathered, and their types" do
      collect_count(Module2, :total, total_term(), 7)

      start()

      assert take_counts() == %{}
      assert take_count_types() == %{}
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

  describe "take/1" do
    test "carries each row with the given user's verdicts" do
      check_permissions()

      row = %{VerdictTask.new() | id: Entity.generate_id()}

      start()
      collect(row)

      assert %{put_entity: %{"Hologram.Sync.CarryTest.VerdictTask" => [carried]}} =
               take(Entity.generate_id())

      assert carried[:"$verdicts"] == %{delete_key() => true}
    end

    test "returns nothing when no result was collected" do
      assert take(nil) == %{}
    end

    # What a render gathered belongs to that render: a second page rendered in the same process
    # would otherwise be seeded with the first one's rows.
    test "leaves nothing behind for the next render" do
      collect([module_2()])

      take(nil)

      assert take(nil) == %{}
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

  describe "take_count_types/0" do
    test "returns nothing when no count was collected" do
      assert take_count_types() == %{}
    end

    test "leaves nothing behind for the next render" do
      collect_count(Module2, :total, total_term(), 7)

      take_count_types()

      assert take_count_types() == %{}
    end
  end

  describe "take_counts/0" do
    test "returns nothing when no count was collected" do
      assert take_counts() == %{}
    end

    test "leaves nothing behind for the next render" do
      collect_count(Module2, :total, total_term(), 7)

      take_counts()

      assert take_counts() == %{}
    end
  end
end
