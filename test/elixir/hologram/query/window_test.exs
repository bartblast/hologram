defmodule Hologram.Query.WindowTest do
  use Hologram.Test.DatabaseCase, async: true
  use Hologram.DB

  import Hologram.Query.Window

  alias Hologram.DB
  alias Hologram.DB.QueryRunner
  alias Hologram.Query
  alias Hologram.Query.Stage
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module17
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module26
  alias Hologram.Test.Fixtures.Entity.Module28
  alias Hologram.Test.Fixtures.Entity.Module29
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module30
  alias Hologram.Test.Fixtures.Entity.Module32
  alias Hologram.Test.Fixtures.Entity.Module33
  alias Hologram.Test.Fixtures.Entity.Module34
  alias Hologram.Test.Fixtures.Entity.Module37
  alias Hologram.Test.Fixtures.Entity.Module38
  alias Hologram.Test.Fixtures.Entity.Module5
  alias Hologram.Test.Fixtures.Entity.Module6
  alias Hologram.Test.Fixtures.Policy

  defp term(entity_type, filter) do
    %{Stage.normalize(entity_type) | filter: filter}
  end

  describe "embed/2 - what it embeds" do
    defmodule WindowProject do
      use Hologram.Entity

      relationship :labels, [Hologram.Query.WindowTest.WindowLabel]
      relationship :members, [Hologram.Query.WindowTest.WindowMember], inverse: project

      allow :read
      allow :update, when: any(member <- members, member.seat == "full")
      allow :update, only: [labels], when: none(labels)
    end

    defmodule WindowMember do
      use Hologram.Entity

      attribute :seat, :string

      relationship :project, WindowProject, optional: true

      allow :read
    end

    defmodule WindowLabel do
      use Hologram.Entity

      allow :read
    end

    defmodule WindowVault do
      use Hologram.Entity

      attribute :open, :boolean

      allow :update
    end

    defmodule WindowShelf do
      use Hologram.Entity

      relationship :vault, WindowVault, optional: true

      allow :read
    end

    defmodule WindowParcel do
      use Hologram.Entity

      relationship :shelf, WindowShelf, optional: true
      relationship :vault, WindowVault, optional: true

      allow :read, when: vault.open == true
      allow :read, when: shelf.vault.open == true
    end

    defmodule WindowCrate do
      use Hologram.Entity

      relationship :parcel, WindowParcel, optional: true

      allow :read
    end

    test "embeds a dropped path predicate's relationships all the same" do
      window = embed(term(Module3, [{[:b, :c], :!=, "x"}]), false)

      assert window.include == %{b: %Query{entity: Module2}}
    end

    test "leaves a path predicate a missing related row satisfies out of an any's set's narrowing" do
      window =
        Module26
        |> filter(any(message <- messages, message.channel.name != "x" and message.position > 1))
        |> Stage.normalize()
        |> embed(false)

      assert window.include.messages.filter == [{:position, :>, 1}]
    end

    test "embeds the relationships of a path operand" do
      window = embed(term(Module3, [{:c_id, :==, {:attribute, [:b, :id]}}]), false)

      assert window.include == %{b: %Query{entity: Module2}}
    end

    test "embeds the relationships of a path inside an alternative" do
      filter = [{:or, [[{[:b, :a], :==, true}], [{:c_id, :==, nil}]]}]

      assert embed(term(Module3, filter), false).include == %{b: %Query{entity: Module2}}
    end

    test "merges a path's relationships into the query's own includes" do
      base_term =
        Module5
        |> include(a)
        |> Stage.normalize()

      term = %{base_term | filter: [{[:a, :b, :c], :==, "x"}]}

      assert embed(term, false).include == %{
               a: %Query{entity: Module3, include: %{b: %Query{entity: Module2}}}
             }
    end

    test "embeds the sets the type's rules read when a client checks permissions" do
      window = embed(Stage.normalize(WindowProject), true)

      assert window.include == %{
               labels: %Query{entity: WindowLabel},
               members: %Query{entity: WindowMember}
             }
    end

    # The query's own quantifier narrows the members to the full seats, and the rule asks about the
    # part ones, so the rule's set comes whole.
    test "embeds a rule's set whole beside a quantifier narrowing it" do
      term =
        WindowProject
        |> Stage.filter(any: {[:members], [seat: "full"]})
        |> Stage.normalize()

      assert embed(term, true).include.members == %Query{entity: WindowMember}
    end

    test "embeds an included type's rule chain only up to its first type nobody may read" do
      term =
        WindowCrate
        |> include(parcel)
        |> Stage.normalize()

      assert embed(term, true).include == %{
               parcel: %Query{
                 entity: WindowParcel,
                 include: %{shelf: %Query{entity: WindowShelf}}
               }
             }
    end

    test "embeds the rows an included type's rules read under the include" do
      term =
        Policy.Module3
        |> include(children)
        |> Stage.normalize()

      assert embed(term, true).include.children.include == %{
               parent: %Query{entity: Policy.Module2}
             }
    end

    # The type's own rules read nothing through the relationship, so the row arrives for the path
    # alone - and the rows its own type's rules read stay out from under it.
    test "embeds no rule's rows under a row embedded for a path" do
      window = embed(term(Policy.Module15, [{[:origin, :level], :==, 1}]), true)

      assert window.include == %{origin: %Query{entity: Policy.Module12}}
    end

    test "embeds no rule's rows under a row embedded for a rule" do
      window = embed(Stage.normalize(Policy.Module8), true)

      assert window.include == %{
               parent: %Query{
                 entity: Policy.Module5,
                 include: %{parent: %Query{entity: Policy.Module1}}
               }
             }
    end

    test "merges a rule's rows into the query's own includes" do
      term =
        Policy.Module1
        |> include(author)
        |> Stage.normalize()

      assert embed(term, true).include == %{
               author: %Query{entity: Module14},
               parent: %Query{entity: Policy.Module2}
             }
    end

    # The row two relationships away is included as written, so its own type's rules are read
    # under it - one row further than anything the queried type's rules read.
    test "embeds the rows a nested include's type's rules read under that include" do
      term =
        Policy.Module8
        |> include(parent.parent)
        |> Stage.normalize()

      assert embed(term, true).include == %{
               parent: %Query{
                 entity: Policy.Module5,
                 include: %{
                   parent: %Query{
                     entity: Policy.Module1,
                     include: %{parent: %Query{entity: Policy.Module2}}
                   }
                 }
               }
             }
    end

    # An inverse of a to-one is read off each related row's own reference field, with no ids filed
    # for the row, so its set is narrowed by the condition like any query.
    test "embeds an any's set read off a reference narrowed by the condition" do
      window =
        Module26
        |> filter(any(message <- messages, message.body == "x"))
        |> Stage.normalize()
        |> embed(false)

      assert window.include == %{messages: %Query{entity: Module28, filter: [{:body, :==, "x"}]}}
    end

    test "embeds whole the set of an any whose condition loses every predicate" do
      filter = [{:any, {[:messages], [{[:channel, :name], :!=, "x"}]}}]

      window = embed(term(Module26, filter), false)

      assert window.include == %{
               messages: %Query{entity: Module28, include: %{channel: %Query{entity: Module26}}}
             }
    end

    test "narrows a none's set and embeds an all's whole" do
      none_window =
        Module26
        |> filter(none(message <- messages, message.body == "x"))
        |> Stage.normalize()
        |> embed(false)

      all_window =
        Module26
        |> filter(all(message <- messages, message.body == "x"))
        |> Stage.normalize()
        |> embed(false)

      assert none_window.include == %{
               messages: %Query{entity: Module28, filter: [{:body, :==, "x"}]}
             }

      assert all_window.include == %{messages: %Query{entity: Module28}}
    end

    test "embeds a set the client reads through ids whole, whatever the condition" do
      stored =
        Module28
        |> filter(any(label <- labels, label.name == "x"))
        |> Stage.normalize()
        |> embed(false)

      inverse =
        Module29
        |> filter(any(message <- messages, message.body == "x"))
        |> Stage.normalize()
        |> embed(false)

      assert stored.include == %{labels: %Query{entity: Module29}}
      assert inverse.include == %{messages: %Query{entity: Module28}}
    end

    test "embeds a set reached through a to-one under it, whole when the condition reads the row above" do
      window =
        Module28
        |> filter(any(message <- channel.messages, message.position > position))
        |> Stage.normalize()
        |> embed(false)

      assert window.include == %{
               channel: %Query{
                 entity: Module26,
                 include: %{messages: %Query{entity: Module28}}
               }
             }
    end

    test "joins two narrowings of one set with or" do
      window =
        Module26
        |> filter(any(message <- messages, message.body == "b"))
        |> filter(any(message <- messages, message.body == "a"))
        |> Stage.normalize()
        |> embed(false)

      assert window.include == %{
               messages: %Query{
                 entity: Module28,
                 filter: [{:or, [[{:body, :==, "a"}], [{:body, :==, "b"}]]}]
               }
             }
    end

    test "embeds a set whole when one of its quantifiers needs it whole" do
      window =
        Module26
        |> filter(any(message <- messages, message.body == "b"))
        |> filter(all(message <- messages, message.position > 1))
        |> Stage.normalize()
        |> embed(false)

      assert window.include == %{messages: %Query{entity: Module28}}
    end

    test "leaves a set the query includes whole as it is" do
      term =
        Module26
        |> filter(any(message <- messages, message.body == "b"))
        |> include(messages)
        |> Stage.normalize()

      assert embed(term, false).include == term.include
    end

    test "embeds a nested set under its parent's, each narrowed by its own condition" do
      window =
        Module26
        |> filter(
          any(
            message <- messages,
            message.body == "b" and any(label <- message.labels, label.name == "u")
          )
        )
        |> Stage.normalize()
        |> embed(false)

      assert window.include == %{
               messages: %Query{
                 entity: Module28,
                 filter: [
                   {:any, {[:labels], [{:name, :==, "u"}]}},
                   {:body, :==, "b"}
                 ],
                 include: %{labels: %Query{entity: Module29}}
               }
             }
    end

    test "embeds a set a source goes through whole and narrows only the last" do
      window =
        Module37
        |> filter(any(message <- messages.channel.messages, message.pinned == true))
        |> Stage.normalize()
        |> embed(false)

      assert window.include == %{
               messages: %Query{
                 entity: Module38,
                 include: %{
                   channel: %Query{
                     entity: Module37,
                     include: %{
                       messages: %Query{entity: Module38, filter: [{:pinned, :==, true}]}
                     }
                   }
                 }
               }
             }
    end

    test "keeps the narrowing of a parent set a nested quantifier's source starts inside" do
      window =
        Module37
        |> filter(
          any(
            message <- messages,
            message.pinned == true and
              any(colleague <- message.channel.messages, colleague.pinned == false)
          )
        )
        |> Stage.normalize()
        |> embed(false)

      assert {:pinned, :==, true} in window.include.messages.filter
    end

    test "embeds whole a set a source read on the row above goes through" do
      window =
        Module37
        |> filter(
          any(
            message <- messages,
            message.pinned == true and
              any(colleague <- messages.channel.messages, colleague.pinned == false)
          )
        )
        |> Stage.normalize()
        |> embed(false)

      assert window.include.messages.filter == []
    end

    test "embeds a set a source goes through whole beside another quantifier narrowing it" do
      window =
        Module37
        |> filter(
          any(message <- messages, message.pinned == true) and
            any(colleague <- messages.channel.messages, colleague.pinned == false)
        )
        |> Stage.normalize()
        |> embed(false)

      assert window.include.messages.filter == []
    end

    test "embeds a set read on the queried row from inside another quantifier on the queried row" do
      window =
        Module30
        |> filter(any(followed <- follows, any(reply <- replies, reply.body == followed.body)))
        |> Stage.normalize()
        |> embed(false)

      assert window.include == %{
               follows: %Query{entity: Module30},
               replies: %Query{entity: Module30}
             }
    end

    test "embeds the rows a path inside a quantifier's condition reads under its set" do
      window =
        Module26
        |> filter(any(message <- messages, message.channel.name == "general"))
        |> Stage.normalize()
        |> embed(false)

      assert window.include == %{
               messages: %Query{
                 entity: Module28,
                 filter: [{[:channel, :name], :==, "general"}],
                 include: %{channel: %Query{entity: Module26}}
               }
             }
    end

    test "joins three narrowings of one set into one disjunction whatever order they come in" do
      first =
        Module26
        |> filter(none(message <- messages, message.body == "a"))
        |> filter(none(message <- messages, message.body == "b"))
        |> filter(none(message <- messages, message.body == "c"))
        |> Stage.normalize()
        |> embed(false)

      second =
        Module26
        |> filter(none(message <- messages, message.body == "c"))
        |> filter(none(message <- messages, message.body == "a"))
        |> filter(none(message <- messages, message.body == "b"))
        |> Stage.normalize()
        |> embed(false)

      assert first.include.messages.filter == [
               {:or, [[{:body, :==, "a"}], [{:body, :==, "b"}], [{:body, :==, "c"}]]}
             ]

      assert first == second
    end

    test "narrows a set by its condition's parts reading no row above it" do
      window =
        Module26
        |> filter(
          any(
            message <- messages,
            (message.body == "a" or message.body == name) and message.position > 1
          )
        )
        |> Stage.normalize()
        |> embed(false)

      assert window.include.messages.filter == [{:position, :>, 1}]
    end

    test "narrows a nested set read off a reference by its own condition" do
      window =
        Module30
        |> filter(any(reply <- replies, any(nested <- reply.replies, nested.body == "y")))
        |> Stage.normalize()
        |> embed(false)

      assert window.include == %{
               replies: %Query{
                 entity: Module30,
                 filter: [{:any, {[:replies], [{:body, :==, "y"}]}}],
                 include: %{replies: %Query{entity: Module30, filter: [{:body, :==, "y"}]}}
               }
             }
    end

    test "narrows a parent set by a nested quantifier reading its row, not by one reading further out" do
      window =
        Module30
        |> filter(
          any(
            reply <- replies,
            any(nested <- reply.replies, nested.body == reply.body) and
              any(nested <- reply.replies, nested.body == body)
          )
        )
        |> Stage.normalize()
        |> embed(false)

      assert window.include.replies.filter == [
               {:any, {[:replies], [{:body, :==, {:attribute, {:outer, 1, :body}}}]}}
             ]
    end
  end

  # A set read off its rows' own reference field is narrowed by the condition that reads it: the
  # messages of a channel, narrowed by an any's condition about them.
  describe "embed/2 - narrowing a set" do
    defp narrowing(clauses) do
      Module26
      |> term([{:any, {[:messages], clauses}}])
      |> embed(false)
      |> Map.fetch!(:include)
      |> Map.fetch!(:messages)
      |> Map.fetch!(:filter)
    end

    test "leaves out a path predicate a missing related row satisfies" do
      for predicate <- [
            {[:channel, :name], :!=, "x"},
            {[:channel, :name], :==, nil},
            {[:channel, :name], :in, [nil, "x"]},
            {[:channel, :name], :not_in, ["x"]},
            {[:channel, :name], :==, {:attribute, :body}},
            {:body, :!=, {:attribute, [:channel, :name]}}
          ] do
        assert narrowing([predicate]) == []
      end
    end

    test "keeps a path predicate a missing related row never satisfies" do
      for predicate <- [
            {[:channel, :name], :==, "x"},
            {[:channel, :name], :!=, nil},
            {[:channel, :name], :in, ["x", "y"]},
            {[:channel, :name], :not_in, [nil, "x"]},
            {[:channel, :name], :contains, "x"},
            {[:channel, :name], :starts_with_exact, "x"}
          ] do
        assert narrowing([predicate]) == [predicate]
      end
    end

    test "narrows an alternative to what bounds it" do
      clauses = [
        {:or, [[{:body, :==, "a"}, {[:channel, :name], :!=, "x"}], [{:position, :==, 1}]]}
      ]

      assert narrowing(clauses) == [{:or, [[{:body, :==, "a"}], [{:position, :==, 1}]]}]
    end

    test "leaves out a disjunction when an alternative loses every predicate" do
      clauses = [{:or, [[{:body, :==, "a"}], [{[:channel, :name], :!=, "x"}]]}]

      assert narrowing(clauses) == []
    end

    test "narrows a nested disjunction the same way" do
      clauses = [
        {:or,
         [
           [
             {:body, :==, "a"},
             {:or, [[{:position, :==, 1}], [{[:channel, :name], :==, nil}]]}
           ],
           [{:position, :==, 2}]
         ]}
      ]

      assert narrowing(clauses) == [{:or, [[{:body, :==, "a"}], [{:position, :==, 2}]]}]
    end

    test "keeps the narrowed alternatives in canonical order" do
      clauses = [
        {:or,
         [
           [{:body, :==, "a"}, {:position, :==, 7}],
           [{:body, :==, "a"}, {[:channel, :name], :in, [nil, "x"]}]
         ]}
      ]

      assert narrowing(clauses) == [
               {:or, [[{:body, :==, "a"}], [{:body, :==, "a"}, {:position, :==, 7}]]}
             ]
    end
  end

  describe "embed/2 - running what it embeds" do
    test "is a query term, runnable as one, with the relationships its paths embed" do
      term =
        Module5
        |> Stage.filter([{[:a, :b, :c], {:>=, "M"}}])
        |> Stage.normalize()
        |> embed(false)

      assert is_list(QueryRunner.run(term, DB.mapping()))
    end

    test "is a query term, runnable as one, with the rows its rules read embedded" do
      term = embed(Stage.normalize(Policy.Module12), true)

      assert is_list(QueryRunner.run(term, DB.mapping()))
    end
  end

  describe "embed/2 - what derived fields read" do
    setup do
      put_derived_definitions([Module32, Module33, Module37, Module38])
    end

    test "embeds the rows a compared derived field is computed from" do
      term =
        Module37
        |> filter(member_count > 3)
        |> Stage.normalize()

      window = embed(term, false)

      assert window.include == %{members: %Query{entity: Module2}}
    end

    test "embeds the rows a derived field a path ends at is computed from" do
      term =
        Module38
        |> filter(channel.pinned_count > 1)
        |> Stage.normalize()

      window = embed(term, false)

      assert window.include == %{
               channel: %Query{
                 entity: Module37,
                 include: %{messages: %Query{entity: Module38, filter: [{:pinned, :==, true}]}}
               }
             }
    end

    test "embeds the rows a quantified derived set is computed from" do
      term =
        Module37
        |> filter(any(message <- recent_messages, message.pinned == true))
        |> Stage.normalize()

      window = embed(term, false)

      assert window.include == %{messages: %Query{entity: Module38}}
    end

    test "narrows a set read off its rows' own reference field by a definition's literal conditions" do
      term =
        Module37
        |> filter(pinned_count > 1)
        |> Stage.normalize()

      window = embed(term, false)

      assert window.include == %{
               messages: %Query{entity: Module38, filter: [{:pinned, :==, true}]}
             }
    end

    test "embeds a set whole for a definition's condition reading the row it belongs to" do
      term =
        Module37
        |> filter(unread_count > 0)
        |> Stage.normalize()

      window = embed(term, false)

      assert window.include == %{messages: %Query{entity: Module38}}
    end

    test "embeds a to-many a definition counts whole" do
      term =
        Module37
        |> filter(member_count > 0)
        |> Stage.normalize()

      window = embed(term, false)

      assert window.include == %{members: %Query{entity: Module2}}
    end

    test "embeds a set a definition reads through a related row" do
      term =
        Module38
        |> filter(sibling_count > 1)
        |> Stage.normalize()

      window = embed(term, false)

      assert window.include == %{
               channel: %Query{entity: Module37, include: %{messages: %Query{entity: Module38}}}
             }
    end

    test "embeds the rows a derived field a definition reads is computed from" do
      term =
        Module37
        |> filter(busy == true)
        |> Stage.normalize()

      window = embed(term, false)

      assert window.include == %{
               messages: %Query{entity: Module38, filter: [{:pinned, :==, true}]}
             }
    end

    test "embeds what a definition's own includes read" do
      term =
        Module37
        |> include(authored_messages)
        |> Stage.normalize()

      window = embed(term, false)

      # A derived field's own include stays as authored, beside the rows it is computed from.
      assert window.include ==
               Map.put(term.include, :messages, %Query{
                 entity: Module38,
                 include: %{author: %Query{entity: Module1}}
               })
    end

    test "embeds what an include of a derived set includes off the rows it is computed from" do
      term =
        Module37
        |> include(recent_messages.author)
        |> Stage.normalize()

      window = embed(term, false)

      assert window.include ==
               Map.put(term.include, :messages, %Query{
                 entity: Module38,
                 include: %{author: %Query{entity: Module1}}
               })
    end

    test "embeds what an include of a set chosen with if includes off every source it reads" do
      term =
        Module37
        |> include(picked.author)
        |> Stage.normalize()

      author = %Query{entity: Module1}

      assert embed(term, false).include == %{
               picked: term.include.picked,
               messages: %Query{
                 entity: Module38,
                 include: %{
                   author: author,
                   channel: %Query{
                     entity: Module37,
                     include: %{messages: %Query{entity: Module38, include: %{author: author}}}
                   }
                 }
               }
             }
    end

    test "embeds every source a set chosen with if reads, for a derived field counting it" do
      term =
        Module37
        |> filter(picked_count > 0)
        |> Stage.normalize()

      assert embed(term, false).include == %{
               messages: %Query{
                 entity: Module38,
                 include: %{
                   channel: %Query{
                     entity: Module37,
                     include: %{messages: %Query{entity: Module38}}
                   }
                 }
               }
             }
    end

    test "embeds every source a set chosen with if reads, for a quantifier over it" do
      term =
        Module37
        |> filter(any(message <- picked, message.pinned == true))
        |> Stage.normalize()

      window = embed(term, false)

      assert window.include == %{
               messages: %Query{
                 entity: Module38,
                 include: %{
                   channel: %Query{
                     entity: Module37,
                     include: %{messages: %Query{entity: Module38}}
                   }
                 }
               }
             }
    end

    test "embeds nothing for an include through a set holding no rows" do
      term =
        Module37
        |> include(nothing.author)
        |> Stage.normalize()

      assert embed(term, false).include == term.include
    end

    test "embeds the rows a derived field a condition of if reads is computed from" do
      put_derived_definitions([Module34])

      term =
        Module34
        |> filter(level == :busy)
        |> Stage.normalize()

      assert embed(term, false).include == %{
               channel: %Query{entity: Module32, include: %{messages: %Query{entity: Module33}}}
             }
    end

    test "embeds the rows a derived field sorted by is computed from" do
      term =
        Module37
        |> sort(member_count)
        |> Stage.normalize()

      window = embed(term, false)

      assert window.include == %{members: %Query{entity: Module2}}
    end

    test "embeds a set a definition's source reads through whole beside a narrowing of it" do
      term =
        Module37
        |> filter(pinned_count > 1)
        |> include(colleague_count)
        |> Stage.normalize()

      assert embed(term, false).include == %{
               colleague_count: nil,
               messages: %Query{
                 entity: Module38,
                 include: %{
                   channel: %Query{
                     entity: Module37,
                     include: %{messages: %Query{entity: Module38}}
                   }
                 }
               }
             }
    end

    test "joins a derived field's narrowing and a quantifier's of one set with or" do
      term =
        Module37
        |> filter(pinned_count > 1 and any(message <- messages, message.pinned == false))
        |> Stage.normalize()

      assert embed(term, false).include == %{
               messages: %Query{
                 entity: Module38,
                 filter: [{:or, [[{:pinned, :==, false}], [{:pinned, :==, true}]]}]
               }
             }
    end

    test "embeds the rows the rules of a derived include's rows read when a client checks them" do
      term =
        Module37
        |> include(recent_messages)
        |> Stage.normalize()

      assert embed(term, true).include == %{
               recent_messages: term.include.recent_messages,
               messages: %Query{entity: Module38, include: %{channel: %Query{entity: Module37}}}
             }
    end

    test "embeds what a derived field read inside a quantifier's condition is computed from" do
      term =
        Module32
        |> filter(any(message <- messages, message.later_count > 2))
        |> Stage.normalize()

      window = embed(term, false)

      assert window.include == %{
               messages: %Query{
                 entity: Module33,
                 include: %{
                   channel: %Query{
                     entity: Module32,
                     include: %{messages: %Query{entity: Module33}}
                   }
                 }
               }
             }
    end
  end

  describe "embed/2" do
    test "leaves a term with no path in its filters as it is" do
      term =
        Module3
        |> filter(c_id == nil)
        |> include(a)
        |> Stage.normalize()

      assert embed(term, false) == term
    end

    # It is the query itself, read with more of the rows it reads - so what it answers stays.
    test "embeds a path's relationships beside the term's own clauses" do
      term =
        Module5
        |> filter(a.b.c == "x")
        |> sort(id: :desc)
        |> take(3)
        |> Stage.normalize()

      assert embed(term, false) == %{
               term
               | include: %{a: %Query{entity: Module3, include: %{b: %Query{entity: Module2}}}}
             }
    end

    test "embeds a path inside an included query's filter into that include" do
      base_term =
        Module6
        |> include(a)
        |> Stage.normalize()

      sub_term = %{base_term.include.a | filter: [{[:b, :a], :==, true}]}
      term = %{base_term | include: %{a: sub_term}}

      assert embed(term, false).include.a == %{sub_term | include: %{b: %Query{entity: Module2}}}
    end

    test "embeds no rule's row of a type nobody may read" do
      term = Stage.normalize(Hologram.Test.Fixtures.Policy.Readers.Module21)

      assert embed(term, true) == term
    end

    test "embeds a rule's chain only up to its first type nobody may read" do
      term = Stage.normalize(Hologram.Query.WindowTest.WindowParcel)

      assert embed(term, true) == %{
               term
               | include: %{shelf: %Query{entity: Hologram.Query.WindowTest.WindowShelf}}
             }
    end

    test "embeds the rows the type's rules read beside the term's own clauses" do
      term =
        Policy.Module12
        |> filter(level > 1)
        |> Stage.normalize()

      assert embed(term, true) == %{
               term
               | include: %{
                   link: %Query{entity: Module17},
                   parent: %Query{
                     entity: Policy.Module5,
                     include: %{
                       parent: %Query{
                         entity: Policy.Module1,
                         include: %{parent: %Query{entity: Policy.Module2}}
                       }
                     }
                   }
                 }
             }
    end

    test "embeds no rule's rows when no client checks permissions" do
      term =
        Policy.Module12
        |> filter(level > 1)
        |> Stage.normalize()

      assert embed(term, false) == term
    end

    test "embeds a quantifier's set narrowed beside the term's own includes" do
      term =
        Module26
        |> filter(none(message <- messages, message.body == "x"))
        |> include(topic)
        |> Stage.normalize()

      assert embed(term, false).include == %{
               messages: %Query{entity: Module28, filter: [{:body, :==, "x"}]},
               topic: term.include.topic
             }
    end

    test "adds a nested quantifier's set under an authored include of its parent" do
      term =
        Module26
        |> filter(any(message <- messages, any(label <- message.labels, label.name == "u")))
        |> include(messages)
        |> Stage.normalize()

      embedded = embed(term, false).include.messages

      assert embedded.filter == term.include.messages.filter
      assert embedded.include == %{labels: %Query{entity: Module29}}
    end

    test "leaves an authored include of a quantifier's set as authored" do
      term =
        Module26
        |> filter(any(message <- messages, message.body == "x"))
        |> include(messages)
        |> Stage.normalize()

      assert embed(term, false).include == term.include
    end

    test "embeds the rows a derived value is computed from beside its include" do
      put_derived_definitions([Module37, Module38])

      term =
        Module37
        |> include(pinned_count)
        |> Stage.normalize()

      assert embed(term, false).include == %{
               messages: %Query{entity: Module38, filter: [{:pinned, :==, true}]},
               pinned_count: nil
             }
    end

    test "embeds every source a set chosen with if reads beside the authored include" do
      put_derived_definitions([Module37, Module38])

      term =
        Module37
        |> include(picked)
        |> Stage.normalize()

      assert embed(term, false).include == %{
               messages: %Query{
                 entity: Module38,
                 include: %{
                   channel: %Query{
                     entity: Module37,
                     include: %{messages: %Query{entity: Module38}}
                   }
                 }
               },
               picked: term.include.picked
             }
    end

    test "embeds two narrowings of one set joined with or" do
      put_derived_definitions([Module37, Module38])

      term =
        Module37
        |> filter(any(message <- messages, message.pinned == false))
        |> include(pinned_count)
        |> Stage.normalize()

      assert embed(term, false).include == %{
               messages: %Query{
                 entity: Module38,
                 filter: [{:or, [[{:pinned, :==, false}], [{:pinned, :==, true}]]}]
               },
               pinned_count: nil
             }
    end

    test "embeds the rows a derived include is computed from beside the authored include" do
      put_derived_definitions([Module37, Module38])

      term =
        Module37
        |> include(recent_messages)
        |> Stage.normalize()

      assert embed(term, false).include == %{
               messages: %Query{entity: Module38},
               recent_messages: term.include.recent_messages
             }
    end

    test "embeds nothing under a derived field's rows" do
      put_derived_definitions([Module37, Module38])

      term =
        Module37
        |> include(recent_messages.sibling_count)
        |> Stage.normalize()

      assert embed(term, false).include.recent_messages == term.include.recent_messages
    end
  end

  describe "entity_types/1" do
    setup do
      put_derived_definitions([Module32, Module33, Module37, Module38])
    end

    test "reads its own type" do
      assert entity_types(Stage.normalize(Module2)) == [Module2]
    end

    test "reads the types a path goes through" do
      term =
        Module3
        |> filter(c.id != nil)
        |> Stage.normalize()

      assert entity_types(term) == [Module1, Module3]
    end

    test "reads the types it includes" do
      term =
        Module32
        |> include(messages)
        |> Stage.normalize()

      assert entity_types(term) == [Module32, Module33]
    end

    test "reads the types a quantifier's set goes through" do
      term =
        Module37
        |> filter(any(members))
        |> count()
        |> Stage.normalize()

      assert entity_types(term) == [Module2, Module37]
    end

    test "reads the types a derived field it filters on is computed from" do
      term =
        Module37
        |> filter(member_count > 3)
        |> count()
        |> Stage.normalize()

      assert entity_types(term) == [Module2, Module37]
    end

    test "reads the types a derived field holding a value it includes is computed from" do
      term =
        Module32
        |> include(message_count)
        |> Stage.normalize()

      assert entity_types(term) == [Module32, Module33]
    end
  end
end
