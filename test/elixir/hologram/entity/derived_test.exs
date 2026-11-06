defmodule Hologram.Entity.DerivedTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Entity.Derived

  alias Hologram.Entity.Derived.RowRef
  alias Hologram.Query
  alias Hologram.Query.RowField
  alias Hologram.Test.Fixtures.Entity.Derived.Module1, as: DerivedModule1
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module26
  alias Hologram.Test.Fixtures.Entity.Module28
  alias Hologram.Test.Fixtures.Entity.Module29
  alias Hologram.Test.Fixtures.Entity.Module32
  alias Hologram.Test.Fixtures.Entity.Module33
  alias Hologram.Test.Fixtures.Entity.Module34
  alias Hologram.Test.Fixtures.Entity.Module37
  alias Hologram.Test.Fixtures.Entity.Module38
  alias Hologram.Test.Fixtures.Entity.Module39
  alias Hologram.Test.Fixtures.Entity.Module40
  alias Hologram.Test.Fixtures.Entity.Module41

  describe "concat/1" do
    test "lowers each operand" do
      operands = [%RowField{owner: Module34, name: :nickname}, " (", "x", ")"]

      assert concat(operands) ==
               {:concat, [{:name, :nickname}, {:value, " ("}, {:value, "x"}, {:value, ")"}]}
    end
  end

  describe "condition/2" do
    test "returns the clauses the predicates hold for a row of the owning type" do
      assert condition(Module34, score: {:>, 0}) == {:condition, [{:score, :>, 0}]}
    end

    test "raises on a name the owning type does not declare" do
      expected_msg =
        "unknown attribute :nothing in Hologram.Test.Fixtures.Entity.Module34 - known attributes: :active, :badge, :channel_id, :channel_load, :created_at, :display_name, :featured, :id, :level, :named_after_channel, :nickname, :ranked, :recent_count, :score, :score_label, :top_score, :updated_at"

      assert_error ArgumentError, expected_msg, fn -> condition(Module34, nothing: 1) end
    end
  end

  describe "definition/2" do
    test "returns the definition put for the field" do
      put_definitions(%{{Module33, :tier} => {:value, :low}})

      assert definition(Module33, :tier) == {:value, :low}
    end

    test "returns the definitions the shared helper resolves" do
      put_derived_definitions([Module32])

      assert definition(Module32, :message_count) ==
               {:query,
                %Query{
                  cardinality: :count,
                  entity: Module33,
                  source: {Module32, [:messages]}
                }}
    end

    test "raises on a field nothing put a definition for" do
      expected_msg =
        "no definition for Hologram.Test.Fixtures.Entity.Module33.unknown - the Hologram compile resolves derived fields"

      assert_error ArgumentError, expected_msg, fn -> definition(Module33, :unknown) end
    end
  end

  describe "expanded_fields/2" do
    # The member name reads the member's display name, which reads the channel's name - an
    # attribute, so the walk ends there.
    test "returns every derived field a reference reads, through the fields it reads" do
      assert expanded_fields(Module39, [{[], :member_name}]) == [
               {Module34, :display_name},
               {Module39, :member_name}
             ]
    end

    test "returns a derived field a path reads on the row it leads to" do
      assert expanded_fields(Module39, [{[:member], :display_name}]) == [
               {Module34, :display_name}
             ]
    end

    test "returns nothing for an attribute" do
      assert expanded_fields(Module39, [{[], :score}]) == []
    end
  end

  describe "field/2" do
    test "stands for an attribute of the row" do
      assert field(Module28, [:position]) == %RowField{owner: Module28, name: :position}
    end

    test "stands for a reference field of the row" do
      assert field(Module28, [:channel_id]) == %RowField{owner: Module28, name: :channel_id}
    end

    test "stands for an attribute of a related row" do
      assert field(Module28, [:channel, :name]) == %RowField{
               owner: Module28,
               name: [:channel, :name]
             }
    end

    test "stands for a derived field holding a value" do
      assert field(Module32, [:message_count]) == %RowField{
               owner: Module32,
               name: :message_count
             }
    end

    test "stands for a related row" do
      assert field(Module28, [:channel]) == %RowRef{owner: Module28, path: [:channel]}
    end

    test "stands for a related row held by an inverse" do
      assert field(Module26, [:topic]) == %RowRef{owner: Module26, path: [:topic]}
    end

    test "reads a set of the row" do
      assert field(Module26, [:messages]) == %Query{
               entity: Module28,
               source: {Module26, [:messages]}
             }
    end

    test "reads a set of a related row" do
      assert field(Module28, [:channel, :messages]) == %Query{
               entity: Module28,
               source: {Module28, [:channel, :messages]}
             }
    end

    test "reads a set through a set" do
      assert field(Module26, [:messages, :labels]) == %Query{
               entity: Module29,
               source: {Module26, [:messages, :labels]}
             }
    end

    test "reads a derived set of a related row" do
      assert field(Module33, [:channel, :recent_messages]) == %Query{
               entity: Module33,
               source: {Module33, [:channel, :recent_messages]}
             }
    end

    test "raises on a derived field holding one row" do
      expected_msg =
        "first_message is a derived field holding one row - include it, or read the rows it is computed from"

      assert_error ArgumentError, expected_msg, fn -> field(Module32, [:first_message]) end
    end

    test "raises on an attribute read through a set" do
      expected_msg =
        "messages.body reads through a set to one value per row of it - a derived field reads a set's rows with a query, or one value of the row through to-one relationships"

      assert_error ArgumentError, expected_msg, fn -> field(Module26, [:messages, :body]) end
    end

    test "raises on an attribute read through an inverse relationship" do
      expected_msg =
        ":topic is an inverse relationship in Hologram.Test.Fixtures.Entity.Module26 - a derived field reads a related row's value through to-one relationships that hold their reference"

      assert_error ArgumentError, expected_msg, fn -> field(Module26, [:topic, :summary]) end
    end

    test "raises on a name the row does not declare" do
      expected_msg =
        "nothing names :nothing, which is not a field of Hologram.Test.Fixtures.Entity.Module28"

      assert_error ArgumentError, expected_msg, fn -> field(Module28, [:nothing]) end
    end

    test "raises on a path through what is no relationship" do
      expected_msg =
        "body.length names :body, which is not a relationship of Hologram.Test.Fixtures.Entity.Module28"

      assert_error ArgumentError, expected_msg, fn -> field(Module28, [:body, :length]) end
    end
  end

  describe "if_value/3" do
    test "picks between the lowered expressions by the condition's clauses" do
      condition = {:condition, [{:score, :>, 0}]}

      assert if_value(condition, %RowField{owner: Module34, name: :nickname}, nil) ==
               {:if, [{:score, :>, 0}], {:name, :nickname}, {:value, nil}}
    end
  end

  describe "lower/1" do
    test "lowers a query over the row's set" do
      term = field(Module26, [:messages])

      assert lower(term) == {:query, term}
    end

    test "lowers a row field to the name it stands for" do
      assert lower(%RowField{owner: Module28, name: [:channel, :name]}) ==
               {:name, [:channel, :name]}
    end

    test "lowers a plain value" do
      assert lower(:low) == {:value, :low}
    end

    test "lowers nil" do
      assert lower(nil) == {:value, nil}
    end

    test "lowers a date" do
      assert lower(~D[2026-11-03]) == {:value, ~D[2026-11-03]}
    end

    test "raises on a query of every row of an entity type" do
      expected_msg =
        "a derived field's query starts from a relationship of the row, got a query of every Hologram.Test.Fixtures.Entity.Module28 - read the rows through an argument naming the relationship"

      assert_error ArgumentError, expected_msg, fn -> lower(%Query{entity: Module28}) end
    end

    test "raises on a value of no derived field's type" do
      expected_msg =
        "a derived field computes a value of its type, a field of the row or a query over its rows, got: [1, 2]"

      assert_error ArgumentError, expected_msg, fn -> lower(wrap_term([1, 2])) end
    end

    test "raises on a related row" do
      expected_msg =
        "channel is a related row - include the relationship, or derive one of its attributes: channel.<attribute>"

      assert_error ArgumentError, expected_msg, fn ->
        lower(%RowRef{owner: Module28, path: [:channel]})
      end
    end
  end

  describe "resolve/2" do
    test "resolves a count over a set of the row" do
      assert resolve(Module32, :message_count) ==
               {:query,
                %Query{
                  cardinality: :count,
                  entity: Module33,
                  source: {Module32, [:messages]}
                }}
    end

    test "resolves a count over a set of a related row compared with a field of the row" do
      assert resolve(Module33, :later_count) ==
               {:query,
                %Query{
                  cardinality: :count,
                  entity: Module33,
                  filter: [{:position, :>, {:attribute, {:outer, 1, :position}}}],
                  source: {Module33, [:channel, :messages]}
                }}
    end

    test "resolves a bounded set in the order it states" do
      assert resolve(Module32, :recent_messages) ==
               {:query,
                %Query{
                  entity: Module33,
                  sort: [{:position, :desc}, {:id, :asc}],
                  source: {Module32, [:messages]},
                  take: 2
                }}
    end

    test "resolves one row of a set" do
      assert resolve(Module32, :first_message) ==
               {:query,
                %Query{
                  cardinality: :one,
                  entity: Module33,
                  sort: [{:position, :asc}, {:id, :asc}],
                  source: {Module32, [:messages]}
                }}
    end

    test "resolves a set stating no order in its set's declared order" do
      assert resolve(Module32, :first_messages) ==
               {:query,
                %Query{
                  entity: Module33,
                  sort: [{:position, :asc}, {:id, :asc}],
                  source: {Module32, [:messages]},
                  take: 3
                }}
    end

    test "resolves an attribute of a related row" do
      assert resolve(Module33, :channel_name) == {:name, [:channel, :name]}
    end

    test "resolves strings joined with fields of the row" do
      assert resolve(Module34, :display_name) ==
               {:concat,
                [{:name, :nickname}, {:value, " ("}, {:name, [:channel, :name]}, {:value, ")"}]}
    end

    test "resolves a value picked by a condition on a derived field" do
      assert resolve(Module34, :level) ==
               {:if, [{:channel_load, :>, 3}], {:value, :busy}, {:value, :quiet}}
    end

    test "resolves if without else to nil when the condition does not hold" do
      assert resolve(Module34, :badge) ==
               {:if, [{:score, :>=, 3}], {:value, "top"}, {:value, nil}}
    end

    test "resolves a boolean field to its condition" do
      assert resolve(Module34, :active) == {:condition, [{:score, :>, 0}, {:score, :<, 3}]}
    end

    test "resolves a condition joined by or with a membership" do
      assert resolve(Module34, :featured) ==
               {:condition, [{:or, [[{:score, :not_in, [0]}], [{:nickname, :==, "lead"}]]}]}
    end

    test "resolves a derived field of a related row" do
      assert resolve(Module34, :channel_load) == {:name, [:channel, :message_count]}
    end

    test "resolves a field compared with a field of a related row" do
      assert resolve(Module34, :named_after_channel) ==
               {:condition, [{:nickname, :==, {:attribute, [:channel, :name]}}]}
    end

    test "resolves memberships in a module attribute and a list, with and inside or" do
      assert resolve(Module34, :ranked) ==
               {:condition,
                [
                  {:or,
                   [
                     [{:score, :in, [1, 2]}],
                     [{[:channel, :name], :in, ["general"]}, {:score, :>, -1}]
                   ]}
                ]}
    end

    test "resolves a pipe of stages over a set of a related row" do
      assert resolve(Module34, :recent_count) ==
               {:query,
                %Query{
                  cardinality: :count,
                  entity: Module33,
                  filter: [{:position, :>, 1}],
                  source: {Module34, [:channel, :messages]}
                }}
    end

    test "resolves if written with a do-block" do
      assert resolve(Module34, :score_label) ==
               {:if, [{:score, :>, 5}], {:value, "high"}, {:value, "low"}}
    end

    test "resolves a module attribute to its value at the declaration's line" do
      assert resolve(Module34, :top_score) == {:value, 10}
    end

    test "resolves a module attribute to its value" do
      assert resolve(Module33, :tier) == {:value, :low}
    end

    test "raises at the field's declaration when its definition can't be built" do
      expected_msg =
        "lib/my_app/channel.ex:7: invalid derived field :broken in Hologram.Test.Fixtures.Entity.Derived.Module1 - unknown relationship :nothing"

      assert_error Hologram.CompileError, expected_msg, fn -> resolve(DerivedModule1, :broken) end
    end
  end

  describe "rows_term/3" do
    test "embeds what the definition includes beside what the field is included with" do
      put_derived_definitions([Module37])

      included_term = %Query{entity: Module38, include: %{channel: %Query{entity: Module37}}}

      assert rows_term(Module37, :authored_messages, included_term) == %Query{
               entity: Module38,
               include: %{
                 author: %Query{entity: Module1},
                 channel: %Query{entity: Module37}
               }
             }
    end

    test "embeds what every query an if may choose includes" do
      put_derived_definitions([Module40])

      assert rows_term(Module40, :picked_notes, %Query{entity: Module41}) == %Query{
               entity: Module41,
               include: %{
                 tags: %Query{entity: Module2, sort: [id: :asc]},
                 team: %Query{entity: Module40}
               }
             }
    end

    test "keeps the definition's include of a relationship both include, gaining what the other includes" do
      put_derived_definitions([Module40])

      included_term = %Query{
        entity: Module41,
        include: %{team: %Query{entity: Module40, include: %{mentors: %Query{entity: Module34}}}}
      }

      assert rows_term(Module40, :picked_notes, included_term).include.team == %Query{
               entity: Module40,
               include: %{mentors: %Query{entity: Module34}}
             }
    end

    test "returns the term a relationship is included with as it is" do
      included_term = %Query{entity: Module33, include: %{channel: %Query{entity: Module32}}}

      assert rows_term(Module32, :messages, included_term) == included_term
    end
  end

  describe "set_reads/2" do
    defmodule ReadBoard do
      use Hologram.Entity

      attribute :min_rank, :integer
      attribute :name, :string

      relationship :cards, [Hologram.Entity.DerivedTest.ReadCard], inverse: board
      relationship :labels, [Hologram.Entity.DerivedTest.ReadTag]
      relationship :pinned_cards, [Hologram.Entity.DerivedTest.ReadCard]

      derived :busy_cards, [Hologram.Entity.DerivedTest.ReadCard], fn cards ->
        filter(cards, tag_count > 1)
      end

      derived :label_count, :integer, fn labels -> count(labels) end

      derived :low_top_cards, [Hologram.Entity.DerivedTest.ReadCard], fn top_cards ->
        filter(top_cards, rank < 3)
      end

      derived :named_cards, [Hologram.Entity.DerivedTest.ReadCard], fn cards, name ->
        filter(cards, any(tag <- tags, tag.name == ^name))
      end

      derived :picked_cards, [Hologram.Entity.DerivedTest.ReadCard], fn cards,
                                                                        label_count,
                                                                        pinned_cards ->
        if label_count > 1, do: take(cards, 1), else: pinned_cards
      end

      derived :ranked_cards, [Hologram.Entity.DerivedTest.ReadCard], fn cards, min_rank ->
        filter(cards, rank >= ^min_rank)
      end

      derived :top_cards, [Hologram.Entity.DerivedTest.ReadCard], fn cards ->
        cards
        |> sort(rank: :desc)
        |> take(2)
      end
    end

    defmodule ReadCard do
      use Hologram.Entity

      attribute :rank, :integer
      attribute :title, :string

      relationship :board, ReadBoard, optional: true
      relationship :tags, [Hologram.Entity.DerivedTest.ReadTag]

      derived :tag_count, :integer, fn tags -> count(tags) end

      derived :title_tag, :string, fn title -> title <> "!" end
    end

    defmodule ReadTag do
      use Hologram.Entity

      attribute :name, :string
    end

    setup do
      put_derived_definitions([ReadBoard, ReadCard])
    end

    defp any_rank(source), do: [{:any, {source, [{:rank, :==, 1}]}}]

    # A normalized query is ordered by its id last.
    test "reads a derived set through its query's chain, with its sort keys" do
      assert set_reads(ReadBoard, any_rank([:top_cards])) ==
               {[{[:cards], :rank}, {[:cards], :id}], [[:cards]]}
    end

    test "reads a derived set past the relationships before it, its filter's pin on its owner" do
      assert set_reads(ReadCard, any_rank([:board, :ranked_cards])) ==
               {[{[:board, :cards], :rank}, {[:board], :min_rank}, {[:board, :cards], :id}],
                [[:board, :cards], [:board]]}
    end

    test "reads the set a count in a derived set's filter counts" do
      assert set_reads(ReadBoard, any_rank([:busy_cards])) ==
               {[{[:cards], :id}, {[:cards], :rank}], [[:cards], [:cards, :tags]]}
    end

    test "reads the chain of each query a derived set's if picks from, and what its condition counts" do
      assert set_reads(ReadBoard, any_rank([:picked_cards])) ==
               {[
                  {[:cards], :id},
                  {[:pinned_cards], :id},
                  {[:cards], :rank},
                  {[:pinned_cards], :rank}
                ], [[:cards], [:pinned_cards], [:labels]]}
    end

    test "reads a derived set built on another one through the other one's reads" do
      assert set_reads(ReadBoard, any_rank([:low_top_cards])) ==
               {[{[:cards], :rank}, {[:cards], :id}], [[:cards]]}
    end

    # The tag's name is compared with the board's, two quantifiers out of the tag.
    test "reads a quantifier in a derived set's filter, its pin on the owner" do
      assert set_reads(ReadBoard, any_rank([:named_cards])) ==
               {[{[:cards, :tags], :name}, {[], :name}, {[:cards], :id}, {[:cards], :rank}],
                [[:cards], [:cards, :tags]]}
    end

    test "reads a derived value a quantifier's condition reads on the set's rows" do
      assert set_reads(ReadBoard, [{:any, {[:cards], [{:title_tag, :==, "x!"}]}}]) ==
               {[{[:cards], :title}], [[:cards]]}
    end

    # The second top_cards is read off every card's board, which is no cycle.
    test "reads a derived set met again further along a chain" do
      clauses = [
        {:any, {[:top_cards], [{:any, {[:board, :top_cards], [{:title, :==, "x"}]}}]}}
      ]

      assert set_reads(ReadBoard, clauses) ==
               {[
                  {[:cards], :rank},
                  {[:cards], :id},
                  {[:cards, :board, :cards], :rank},
                  {[:cards, :board, :cards], :id},
                  {[:cards, :board, :cards], :title}
                ], [[:cards], [:cards, :board, :cards]]}
    end

    test "reads the set a count on the row a quantifier's condition pins counts" do
      clauses = [{:none, {[:cards], [{:rank, :>, {:attribute, {:outer, 1, :label_count}}}]}}]

      assert set_reads(ReadBoard, clauses) == {[{[:cards], :rank}], [[:cards], [:labels]]}
    end

    test "keeps the names read outside any quantifier" do
      assert set_reads(ReadBoard, [{:min_rank, :==, 1}, {:label_count, :>, 1}]) ==
               {[{[], :min_rank}, {[], :label_count}], []}
    end
  end
end
