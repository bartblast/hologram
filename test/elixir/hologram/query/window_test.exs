defmodule Hologram.Query.WindowTest do
  use Hologram.Test.DatabaseCase, async: true
  use Hologram.DB

  import Hologram.Query.Window

  alias Hologram.DB
  alias Hologram.DB.QueryRunner
  alias Hologram.Query
  alias Hologram.Query.Registry
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
  alias Hologram.Test.Fixtures.Entity.Module5
  alias Hologram.Test.Fixtures.Entity.Module6
  alias Hologram.Test.Fixtures.Policy

  defp term(entity_type, filter) do
    %{Stage.normalize(entity_type) | filter: filter}
  end

  describe "derive/2" do
    test "downloads the type the query reads" do
      assert derive(Stage.normalize(Module2), false).entity == Module2
    end

    test "keeps a predicate comparing to a literal" do
      window = derive(term(Module2, [{:a, :==, true}]), false)

      assert window.filter == [{:a, :==, true}]
    end

    # A comparison between two attributes says something about the row whatever value anything
    # takes, so it bounds the download the way a literal comparison does.
    test "keeps a predicate comparing two attributes" do
      window = derive(term(Module2, [{:updated_at, :>, {:attribute, :created_at}}]), false)

      assert window.filter == [{:updated_at, :>, {:attribute, :created_at}}]
    end

    test "keeps a path predicate comparing to a literal" do
      window = derive(term(Module3, [{[:b, :a], :==, true}]), false)

      assert window.filter == [{[:b, :a], :==, true}]
    end

    test "drops a predicate comparing to a placeholder" do
      window = derive(term(Module2, [{:c, :==, {:placeholder, :search}}]), false)

      assert window.filter == []
    end

    test "drops a predicate whose attribute is a placeholder" do
      window = derive(term(Module2, [{{:placeholder, :field}, :==, 5}]), false)

      assert window.filter == []
    end

    test "keeps the literal predicates of a query that also has placeholder ones" do
      filter = [
        {:a, :==, true},
        {:c, :==, {:placeholder, :search}},
        {{:placeholder, :field}, :==, 5}
      ]

      window = derive(term(Module2, filter), false)

      assert window.filter == [{:a, :==, true}]
    end

    test "drops a placeholder predicate whatever the operator compares" do
      filter = [
        {:b, :!=, {:placeholder, :excluded}},
        {:b, :<, {:placeholder, :upper}},
        {:b, :>, {:placeholder, :lower}},
        {:b, :in, {:placeholder, :allowed}},
        {:b, :not_in, {:placeholder, :denied}}
      ]

      window = derive(term(Module2, filter), false)

      assert window.filter == []
    end

    # The query answers for every value the placeholder takes, over the rows the path reads - so
    # they are downloaded even when nothing about them bounds the download.
    test "drops a path predicate comparing to a placeholder and embeds its relationships" do
      window = derive(term(Module5, [{[:a, :b, :c], :==, {:placeholder, :search}}]), false)

      assert window.filter == []

      assert window.include == %{
               a: %Query{entity: Module3, include: %{b: %Query{entity: Module2}}}
             }
    end

    test "drops a membership predicate holding a placeholder among its values" do
      window = derive(term(Module2, [{:b, :in, [1, {:placeholder, :chosen}]}]), false)

      assert window.filter == []
    end

    test "keeps a disjunction whose alternatives compare to literals" do
      filter = [{:or, [[{:a, :==, true}], [{:b, :==, 1}]]}]

      assert derive(term(Module2, filter), false).filter == filter
    end

    test "narrows an alternative to its literal predicates" do
      filter = [{:or, [[{:a, :==, true}, {:c, :==, {:placeholder, :search}}], [{:b, :==, 1}]]}]

      assert derive(term(Module2, filter), false).filter == [
               {:or, [[{:a, :==, true}], [{:b, :==, 1}]]}
             ]
    end

    # Dropping the placeholder side alone would download only the todo rows, while the query also
    # answers for whichever rows the placeholder picks - so the alternative admits every row, and
    # the disjunction bounds nothing.
    test "drops a disjunction when an alternative loses every predicate" do
      filter = [{:or, [[{:c, :==, "todo"}], [{:b, :==, {:placeholder, :owner}}]]}]

      assert derive(term(Module2, filter), false).filter == []
    end

    test "keeps the predicates beside a dropped disjunction" do
      filter = [
        {:or, [[{:c, :==, "todo"}], [{:b, :==, {:placeholder, :owner}}]]},
        {:a, :==, true}
      ]

      assert derive(term(Module2, filter), false).filter == [{:a, :==, true}]
    end

    test "drops a nested disjunction the same way" do
      filter = [
        {:or,
         [
           [{:a, :==, true}, {:or, [[{:b, :==, 1}], [{:c, :==, {:placeholder, :search}}]]}],
           [{:b, :==, 2}]
         ]}
      ]

      assert derive(term(Module2, filter), false).filter == [
               {:or, [[{:a, :==, true}], [{:b, :==, 2}]]}
             ]
    end

    test "drops an outer disjunction when a nested one empties its alternative" do
      filter = [
        {:or,
         [[{:or, [[{:b, :==, 1}], [{:c, :==, {:placeholder, :search}}]]}], [{:a, :==, true}]]}
      ]

      assert derive(term(Module2, filter), false).filter == []
    end

    # Narrowing the second alternative leaves it shorter than the first, which moves it ahead.
    test "keeps the narrowed alternatives in canonical order" do
      filter = [
        {:or,
         [
           [{:a, :==, true}, {:b, :==, 7}],
           [{:a, :==, true}, {:b, :>=, {:placeholder, :min}}]
         ]}
      ]

      assert derive(term(Module2, filter), false).filter == [
               {:or, [[{:a, :==, true}], [{:a, :==, true}, {:b, :==, 7}]]}
             ]
    end

    test "gives two queries differing only in a pinned predicate of an alternative one window" do
      bounded = [{:or, [[{:c, :==, "x"}, {:b, :>=, {:placeholder, :min}}], [{:a, :==, true}]]}]
      chosen = [{:or, [[{:c, :==, "x"}, {:b, :==, {:placeholder, :one}}], [{:a, :==, true}]]}]

      assert derive(term(Module2, bounded), false) == derive(term(Module2, chosen), false)
    end

    test "leaves out what a query answers rather than downloads" do
      term =
        Module2
        |> filter(a: true)
        |> sort(c)
        |> take(20)
        |> skip(40)
        |> Stage.normalize()

      assert derive(term, false) == %Query{entity: Module2, filter: [{:a, :==, true}]}
    end

    # A window is not a description of a query, it IS one, and it gets run - so it has to be a
    # term every reader of terms accepts, saying it asks for every row in no order rather than
    # leaving the question out.
    test "is a query term, runnable as one" do
      window =
        Module2
        |> filter(a: true)
        |> sort(c)
        |> Stage.normalize()
        |> derive(false)

      assert is_list(QueryRunner.run(window, DB.mapping()))
    end

    test "embeds the relationships of a path operand" do
      window = derive(term(Module3, [{:c_id, :==, {:attribute, [:b, :id]}}]), false)

      assert window.include == %{b: %Query{entity: Module2}}
    end

    test "embeds the relationships of a path inside an alternative" do
      filter = [{:or, [[{[:b, :a], :==, true}], [{:c_id, :==, nil}]]}]

      assert derive(term(Module3, filter), false).include == %{b: %Query{entity: Module2}}
    end

    test "embeds the relationships a path goes through inside an included query's window" do
      base_term =
        Module26
        |> include(messages)
        |> Stage.normalize()

      sub_term = %{base_term.include.messages | filter: [{[:channel, :name], :==, "general"}]}
      term = %{base_term | include: %{messages: sub_term}}

      assert derive(term, false).include.messages.include == %{
               channel: %Query{entity: Module26}
             }
    end

    test "embeds the relationships a path reads inside an included to-many downloaded whole" do
      term =
        Module6
        |> include(a, &filter(&1, b.a == true))
        |> Stage.normalize()

      assert derive(term, false).include.a == %Query{
               entity: Module3,
               include: %{b: %Query{entity: Module2}}
             }
    end

    test "embeds the relationships a path reads inside an included inverse of a to-many downloaded whole" do
      term =
        Module29
        |> include(messages, &filter(&1, channel.name == "general"))
        |> Stage.normalize()

      assert derive(term, false).include.messages == %Query{
               entity: Module28,
               include: %{channel: %Query{entity: Module26}}
             }
    end

    test "downloads a to-many included under a to-many whole too" do
      term =
        Module6
        |> include(a, &include(&1, a, fn nested -> filter(nested, a == true) end))
        |> Stage.normalize()

      assert derive(term, false).include.a.include.a == %Query{entity: Module2}
    end

    test "keeps the narrowing of an inverse of a to-one included under a set downloaded whole" do
      term =
        Module29
        |> include(messages.channel.messages, &filter(&1, position == 1))
        |> Stage.normalize()

      assert derive(term, false).include.messages.include.channel.include.messages ==
               %Query{entity: Module28, filter: [{:position, :==, 1}]}
    end

    test "merges a path's relationships into the query's own includes" do
      base_term =
        Module5
        |> include(a)
        |> Stage.normalize()

      term = %{base_term | filter: [{[:a, :b, :c], :==, "x"}]}

      assert derive(term, false).include == %{
               a: %Query{entity: Module3, include: %{b: %Query{entity: Module2}}}
             }
    end

    test "is a query term, runnable as one, with the relationships its paths embed" do
      window =
        Module5
        |> Stage.filter([{[:a, :b, :c], {:>=, "M"}}])
        |> Stage.normalize()
        |> derive(false)

      assert is_list(QueryRunner.run(window, DB.mapping()))
    end

    # The rows along the condition paths, the row before a role reference's last relationship and the
    # rows a delegation reads, two rows away and three - each hop embedded once.
    test "embeds the rows the type's rules read when a client checks permissions" do
      window = derive(Stage.normalize(Policy.Module12), true)

      assert window.include == %{
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
    end

    test "embeds no rule's rows when no client checks permissions" do
      assert derive(Stage.normalize(Policy.Module12), false).include == %{}
    end

    test "embeds the rows an included type's rules read under the include" do
      term =
        Policy.Module3
        |> include(children)
        |> Stage.normalize()

      assert derive(term, true).include.children.include == %{
               parent: %Query{entity: Policy.Module2}
             }
    end

    # The type's own rules read nothing through the relationship, so the row arrives for the path
    # alone - and the rows its own type's rules read stay out from under it.
    test "embeds no rule's rows under a row embedded for a path" do
      window = derive(term(Policy.Module15, [{[:origin, :level], :==, 1}]), true)

      assert window.include == %{origin: %Query{entity: Policy.Module12}}
    end

    test "embeds no rule's rows under a row embedded for a rule" do
      window = derive(Stage.normalize(Policy.Module8), true)

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

      assert derive(term, true).include == %{
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

      assert derive(term, true).include == %{
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

    test "is a query term, runnable as one, with the rows its rules read embedded" do
      window = derive(Stage.normalize(Policy.Module12), true)

      assert is_list(QueryRunner.run(window, DB.mapping()))
    end

    # An inverse of a to-one is read off each related row's own reference field, with no ids filed
    # for the row, so its window keeps a literal narrowing like any query.
    test "derives the window of an included query too" do
      base_term =
        Module26
        |> include(messages)
        |> Stage.normalize()

      sub_term = %{
        base_term.include.messages
        | filter: [{:body, :==, {:placeholder, :search}}, {:position, :==, 1}]
      }

      term = %{base_term | include: %{messages: sub_term}}

      assert derive(term, false).include.messages == %Query{
               entity: Module28,
               filter: [{:position, :==, 1}]
             }
    end

    test "downloads an included to-many whole, whatever its query narrows" do
      term =
        Module3
        |> include(a, &filter(&1, a == true))
        |> Stage.normalize()

      assert derive(term, false).include.a == %Query{entity: Module2}
    end

    test "downloads an included inverse of a to-many whole, whatever its query narrows" do
      term =
        Module29
        |> include(messages, &filter(&1, position == 1))
        |> Stage.normalize()

      assert derive(term, false).include.messages == %Query{entity: Module28}
    end

    # Every window holding a row shares the one set the client files for it, so a window narrowing
    # the set would overwrite the complete one another window reads - and report an edge outside
    # its narrowing as gone.
    test "runs to every related row of an included to-many, whatever its query narrows" do
      red =
        %{a: true, c: "red"}
        |> Module2.new()
        |> DB.create!()

      blue =
        %{a: false, c: "blue"}
        |> Module2.new()
        |> DB.create!()

      required = DB.create!(Module1.new())

      source =
        %{c_id: required.id}
        |> Module3.new()
        |> DB.create!()

      source
      |> add_relationship(:a, red.id)
      |> add_relationship(:a, blue.id)
      |> DB.update!()

      window =
        Module3
        |> include(a, &filter(&1, a == true))
        |> Stage.normalize()
        |> derive(false)
        |> Stage.normalize()

      assert [row] = QueryRunner.run(window, DB.mapping())

      assert row.a
             |> Enum.map(& &1.id)
             |> Enum.sort() == Enum.sort([red.id, blue.id])
    end

    test "gives two queries choosing different values one window" do
      searched = derive(term(Module2, [{:c, :==, {:placeholder, :search}}]), false)
      chosen = derive(term(Module2, [{:a, :==, {:placeholder, :flag}}]), false)

      assert searched == chosen
    end

    # Bounding it needs the thirty days written into the query, which the filter surface does not
    # offer yet - a cutoff computed per render says nothing when the window is derived.
    test "downloads a channel's whole history when its recency bound is a placeholder" do
      filter = [{:c, :==, "channel-1"}, {:b, :>, {:placeholder, :cutoff}}]

      window = derive(term(Module2, filter), false)

      assert window.filter == [{:c, :==, "channel-1"}]
    end

    test "keeps an any and embeds its set read off a reference narrowed by the condition" do
      window =
        Module26
        |> filter(any(message <- messages, message.body == "x"))
        |> Stage.normalize()
        |> derive(false)

      assert window.filter == [{:any, {[:messages], [{:body, :==, "x"}]}}]
      assert window.include == %{messages: %Query{entity: Module28, filter: [{:body, :==, "x"}]}}
    end

    test "narrows an any's condition and its set by dropping a placeholder" do
      filter = [
        {:any, {[:messages], [{:body, :==, {:placeholder, :body}}, {:position, :>, 2}]}}
      ]

      window = derive(term(Module26, filter), false)

      assert window.filter == [{:any, {[:messages], [{:position, :>, 2}]}}]
      assert window.include == %{messages: %Query{entity: Module28, filter: [{:position, :>, 2}]}}
    end

    test "keeps an any whose condition loses every predicate, and downloads its set whole" do
      filter = [{:any, {[:messages], [{:body, :==, {:placeholder, :body}}]}}]

      window = derive(term(Module26, filter), false)

      assert window.filter == [{:any, {[:messages], []}}]
      assert window.include == %{messages: %Query{entity: Module28}}
    end

    test "drops a none and an all, narrowing a none's set and downloading an all's whole" do
      none_window =
        Module26
        |> filter(none(message <- messages, message.body == "x"))
        |> Stage.normalize()
        |> derive(false)

      all_window =
        Module26
        |> filter(all(message <- messages, message.body == "x"))
        |> Stage.normalize()
        |> derive(false)

      assert none_window.filter == []

      assert none_window.include == %{
               messages: %Query{entity: Module28, filter: [{:body, :==, "x"}]}
             }

      assert all_window.filter == []
      assert all_window.include == %{messages: %Query{entity: Module28}}
    end

    test "drops a disjunction whose alternative held only a none" do
      window =
        Module26
        |> filter(name == "a" or none(messages))
        |> Stage.normalize()
        |> derive(false)

      assert window.filter == []
    end

    test "downloads a set the client reads through ids whole, whatever the condition" do
      stored =
        Module28
        |> filter(any(label <- labels, label.name == "x"))
        |> Stage.normalize()
        |> derive(false)

      inverse =
        Module29
        |> filter(any(message <- messages, message.body == "x"))
        |> Stage.normalize()
        |> derive(false)

      assert stored.include == %{labels: %Query{entity: Module29}}
      assert inverse.include == %{messages: %Query{entity: Module28}}
    end

    test "embeds a set reached through a to-one under it, whole when the condition reads the row above" do
      window =
        Module28
        |> filter(any(message <- channel.messages, message.position > position))
        |> Stage.normalize()
        |> derive(false)

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
        |> derive(false)

      assert window.include == %{
               messages: %Query{
                 entity: Module28,
                 filter: [{:or, [[{:body, :==, "a"}], [{:body, :==, "b"}]]}]
               }
             }
    end

    test "downloads a set whole when one of its quantifiers needs it whole" do
      window =
        Module26
        |> filter(any(message <- messages, message.body == "b"))
        |> filter(all(message <- messages, message.position > 1))
        |> Stage.normalize()
        |> derive(false)

      assert window.include == %{messages: %Query{entity: Module28}}
    end

    test "leaves a set the query includes whole as it is" do
      window =
        Module26
        |> filter(any(message <- messages, message.body == "b"))
        |> include(messages)
        |> Stage.normalize()
        |> derive(false)

      assert window.include == %{messages: %Query{entity: Module28}}
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
        |> derive(false)

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

    test "embeds a set read on the queried row from inside another quantifier on the queried row" do
      window =
        Module30
        |> filter(any(followed <- follows, any(reply <- replies, reply.body == followed.body)))
        |> Stage.normalize()
        |> derive(false)

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
        |> derive(false)

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
        |> filter(none(message <- messages, message.body == "b"))
        |> filter(none(message <- messages, message.body == "c"))
        |> include(messages, &filter(&1, body == "a"))
        |> Stage.normalize()
        |> derive(false)

      second =
        Module26
        |> filter(none(message <- messages, message.body == "a"))
        |> filter(none(message <- messages, message.body == "c"))
        |> include(messages, &filter(&1, body == "b"))
        |> Stage.normalize()
        |> derive(false)

      assert first.include.messages.filter == [
               {:or, [[{:body, :==, "a"}], [{:body, :==, "b"}], [{:body, :==, "c"}]]}
             ]

      assert first == second
    end

    test "joins a quantifier's narrowing with an authored narrowing of the set" do
      window =
        Module26
        |> filter(any(message <- messages, message.body == "x"))
        |> include(messages, &filter(&1, position > 3))
        |> Stage.normalize()
        |> derive(false)

      assert window.include.messages.filter == [
               {:or, [[{:body, :==, "x"}], [{:position, :>, 3}]]}
             ]
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
        |> derive(false)

      assert window.include.messages.filter == [{:position, :>, 1}]
    end

    test "narrows a nested set read off a reference by its own condition" do
      window =
        Module30
        |> filter(any(reply <- replies, any(nested <- reply.replies, nested.body == "y")))
        |> Stage.normalize()
        |> derive(false)

      assert window.include == %{
               replies: %Query{
                 entity: Module30,
                 filter: [{:any, {[:replies], [{:body, :==, "y"}]}}],
                 include: %{replies: %Query{entity: Module30, filter: [{:body, :==, "y"}]}}
               }
             }
    end

    test "keeps a nested quantifier reading its parent's row in the parent set's narrowing, and drops one reading further out" do
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
        |> derive(false)

      assert window.include.replies.filter == [
               {:any, {[:replies], [{:body, :==, {:attribute, {:outer, 1, :body}}}]}}
             ]
    end

    test "drops a none and an all holding a placeholder" do
      filter = [
        {:none, {[:messages], [{:body, :==, {:placeholder, :body}}]}},
        {:all, {[:messages], [{:position, :>, {:placeholder, :min}}]}}
      ]

      assert derive(term(Module26, filter), false).filter == []
    end

    test "gives the window the types its quantifiers' sets hold" do
      window =
        Module26
        |> filter(any(messages))
        |> Stage.normalize()
        |> derive(false)

      assert Registry.entity_types(window) == MapSet.new([Module26, Module28])
    end

    test "gives two queries differing only in a pinned value inside an any one window" do
      first =
        derive(term(Module26, [{:any, {[:messages], [{:body, :==, {:placeholder, :a}}]}}]), false)

      second =
        derive(
          term(Module26, [{:any, {[:messages], [{:position, :==, {:placeholder, :b}}]}}]),
          false
        )

      assert first == second
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
        |> include(messages, &filter(&1, position > 3))
        |> Stage.normalize()

      embedded = embed(term, false).include.messages

      assert embedded.filter == term.include.messages.filter
      assert embedded.include == %{labels: %Query{entity: Module29}}
    end

    test "leaves an authored include of a quantifier's set as authored" do
      term =
        Module26
        |> filter(any(message <- messages, message.body == "x"))
        |> include(messages, &filter(&1, position > 3))
        |> Stage.normalize()

      assert embed(term, false).include == term.include
    end
  end
end
