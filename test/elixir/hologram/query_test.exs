defmodule Hologram.QueryTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Query

  alias Hologram.Query
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module24
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module5

  describe "filter/2" do
    test "appends to a query held in a variable" do
      query = filter(Module2, a: true)

      assert filter(query, b > 1).filter == [{:a, :==, true}, {:b, :>, 1}]
    end

    test "composes in a pipe" do
      query =
        Module2
        |> filter(a: true)
        |> filter(b > 1)

      assert query.filter == [{:a, :==, true}, {:b, :>, 1}]
    end

    test "lowers a comparison" do
      assert filter(Module2, b >= 3) == %Query{entity: Module2, filter: [{:b, :>=, 3}]}
    end

    test "lowers a comparison with an attribute" do
      assert filter(Module24, ends_on < starts_on).filter == [
               {:ends_on, :<, {:attribute, :starts_on}}
             ]
    end

    test "lowers a conjunction" do
      assert filter(Module2, a == true and b < 10).filter == [{:a, :==, true}, {:b, :<, 10}]
    end

    test "lowers a membership in a pinned list" do
      values = [1, 2]

      assert filter(Module2, b in ^values).filter == [{:b, :in, [1, 2]}]
    end

    test "lowers a negated membership" do
      assert filter(Module2, c not in ["x"]).filter == [{:c, :not_in, ["x"]}]
    end

    test "lowers a pinned operand" do
      min = 3

      assert filter(Module2, b >= ^min).filter == [{:b, :>=, 3}]
    end

    test "lowers a range membership into bound triples" do
      assert filter(Module2, b in 3..5).filter == [{:b, :>=, 3}, {:b, :<=, 5}]
    end

    test "lowers an equality with nil" do
      assert filter(Module2, b == nil).filter == [{:b, :==, nil}]
    end

    test "lowers keyword equality with a pin" do
      search = "x"

      assert filter(Module2, a: true, c: ^search).filter == [{:a, :==, true}, {:c, :==, "x"}]
    end

    test "takes a pinned predicates list" do
      predicates = [b: {:>=, 3}, c: ["x", "y"]]

      assert filter(Module2, ^predicates).filter == [{:b, :>=, 3}, {:c, :in, ["x", "y"]}]
    end

    test "raises the lowering's compile error" do
      code = """
      import Hologram.Query
      filter(Hologram.Test.Fixtures.Entity.Module2, c: search)
      """

      assert_error Hologram.CompileError,
                   "nofile:2: search reads as an attribute of the queried entity, and a keyword predicate value is a literal or a pinned expression - a value from the surrounding code is pinned: ^search, and a comparison with an attribute is written as an expression: c == search",
                   fn -> Code.eval_string(code) end
    end
  end

  describe "include/2" do
    test "lowers a bare name" do
      assert include(Module3, a).include == %{a: %Query{entity: Module2}}
    end

    test "lowers a keyword entry with an in-place sub-builder" do
      query = include(Module3, a: &filter(&1, a: true))

      assert query.include == %{a: %Query{entity: Module2, filter: [{:a, :==, true}]}}
    end

    test "lowers a list of paths" do
      query = include(Module5, [a.a, a.b])

      assert query.include == %{
               a: %Query{
                 entity: Module3,
                 include: %{a: %Query{entity: Module2}, b: %Query{entity: Module2}}
               }
             }
    end

    test "lowers a path" do
      query = include(Module5, a.a)

      assert query.include == %{
               a: %Query{entity: Module3, include: %{a: %Query{entity: Module2}}}
             }
    end

    test "merges two calls through one relationship" do
      query =
        Module5
        |> include(a.a)
        |> include(a.b)

      assert query.include == %{
               a: %Query{
                 entity: Module3,
                 include: %{a: %Query{entity: Module2}, b: %Query{entity: Module2}}
               }
             }
    end

    test "takes a pinned name" do
      relationship = :a

      assert include(Module3, ^relationship).include == %{a: %Query{entity: Module2}}
    end

    test "raises the lowering's compile error" do
      code = """
      import Hologram.Query
      include(Hologram.Test.Fixtures.Entity.Module3, :a)
      """

      assert_error Hologram.CompileError,
                   "nofile:2: include names a relationship with a bare name, got: :a - write a",
                   fn -> Code.eval_string(code) end
    end
  end

  describe "include/3" do
    test "lowers a path with a sub-builder" do
      query = include(Module5, a.a, &filter(&1, a: true))

      assert query.include == %{
               a: %Query{
                 entity: Module3,
                 include: %{a: %Query{entity: Module2, filter: [{:a, :==, true}]}}
               }
             }
    end

    test "lowers an in-place fn" do
      query = include(Module3, a, fn related -> filter(related, a: true) end)

      assert query.include == %{a: %Query{entity: Module2, filter: [{:a, :==, true}]}}
    end

    test "takes a pinned sub-builder" do
      sub_builder = &filter(&1, a: true)

      query = include(Module3, a, ^sub_builder)

      assert query.include == %{a: %Query{entity: Module2, filter: [{:a, :==, true}]}}
    end

    test "raises on a pinned sub-builder that is not a function, through a path" do
      not_a_sub_builder = :a

      assert_error ArgumentError,
                   "include sub-builder for relationship :a must be a one-argument function, got: :a",
                   fn -> include(Module5, a.a, ^not_a_sub_builder) end
    end

    test "raises the lowering's compile error" do
      code = """
      import Hologram.Query
      include(Hologram.Test.Fixtures.Entity.Module3, a, sub_builder)
      """

      assert_error Hologram.CompileError,
                   "nofile:2: include/3 takes a sub-builder written in place (fn or &) or a pinned expression, got: sub_builder - a value from the surrounding code is pinned: ^sub_builder",
                   fn -> Code.eval_string(code) end
    end
  end

  describe "inspect/2" do
    test "leaves out every field at its default" do
      assert inspect(%Query{entity: Module2}) ==
               "%Hologram.Query{entity: Hologram.Test.Fixtures.Entity.Module2}"
    end

    test "prints the literal that rebuilds the term" do
      term =
        Module3
        |> filter(c_id: "x")
        |> include(a, &filter(&1, a: true))
        |> limit(5)
        |> one()

      printed = inspect(term)

      {rebuilt, []} = Code.eval_string(printed)

      assert rebuilt == term
    end

    test "shows a counting cardinality before the entity" do
      assert inspect(count(Module2)) ==
               "%Hologram.Query{cardinality: :count, entity: Hologram.Test.Fixtures.Entity.Module2}"
    end

    test "shows an include as its nested struct" do
      term = include(Module3, a, &filter(&1, a: true))

      assert inspect(term) ==
               "%Hologram.Query{entity: Hologram.Test.Fixtures.Entity.Module3, include: %{a: %Hologram.Query{entity: Hologram.Test.Fixtures.Entity.Module2, filter: [{:a, :==, true}]}}}"
    end

    test "shows the filter as its triples" do
      assert inspect(filter(Module2, a == true and b > 1)) ==
               "%Hologram.Query{entity: Hologram.Test.Fixtures.Entity.Module2, filter: [{:a, :==, true}, {:b, :>, 1}]}"
    end

    test "shows the ordering and the view bounds" do
      term =
        Module2
        |> sort(c)
        |> paginate(page: 3, size: 20)

      assert inspect(term) ==
               "%Hologram.Query{entity: Hologram.Test.Fixtures.Entity.Module2, skip: 40, sort: [c: :asc], take: 20}"
    end

    test "shows the trust mark" do
      assert inspect(trust(Module2)) ==
               "%Hologram.Query{entity: Hologram.Test.Fixtures.Entity.Module2, trust: true}"
    end
  end

  describe "limit/2" do
    test "lowers a literal" do
      assert limit(Module2, 5).take == 5
    end

    test "lowers a pinned bound" do
      page_size = 20

      assert limit(Module2, ^page_size).take == 20
    end

    test "raises the lowering's compile error" do
      code = """
      import Hologram.Query
      limit(Hologram.Test.Fixtures.Entity.Module2, page_size)
      """

      assert_error Hologram.CompileError,
                   "nofile:2: limit takes an integer or a pinned expression, got: page_size - a value from the surrounding code is pinned: ^page_size",
                   fn -> Code.eval_string(code) end
    end
  end

  describe "offset/2" do
    test "lowers a literal" do
      assert offset(Module2, 40).skip == 40
    end

    test "lowers a pinned bound" do
      skip = 40

      assert offset(Module2, ^skip).skip == 40
    end

    test "raises the lowering's compile error" do
      code = """
      import Hologram.Query
      offset(Hologram.Test.Fixtures.Entity.Module2, skip)
      """

      assert_error Hologram.CompileError,
                   "nofile:2: offset takes an integer or a pinned expression, got: skip - a value from the surrounding code is pinned: ^skip",
                   fn -> Code.eval_string(code) end
    end
  end

  describe "paginate/2" do
    test "lowers a pinned option" do
      page = 3

      query = paginate(Module2, page: ^page, size: 20)

      assert {query.skip, query.take} == {40, 20}
    end

    test "takes pinned options" do
      opts = [page: 1, size: 10]

      query = paginate(Module2, ^opts)

      assert {query.skip, query.take} == {0, 10}
    end

    test "raises the lowering's compile error" do
      code = """
      import Hologram.Query
      paginate(Hologram.Test.Fixtures.Entity.Module2, page: page, size: 20)
      """

      assert_error Hologram.CompileError,
                   "nofile:2: a paginate option takes an integer or a pinned expression, got: page - a value from the surrounding code is pinned: ^page",
                   fn -> Code.eval_string(code) end
    end
  end

  describe "sort/2" do
    test "lowers a bare name" do
      assert sort(Module2, c).sort == [c: :asc]
    end

    test "lowers a keyword list with a pinned direction" do
      direction = :desc

      assert sort(Module2, c: ^direction).sort == [c: :desc]
    end

    test "lowers a list of bare names" do
      assert sort(Module2, [a, c]).sort == [a: :asc, c: :asc]
    end

    test "takes a pinned spec" do
      spec = [c: :desc]

      assert sort(Module2, ^spec).sort == [c: :desc]
    end

    test "raises the lowering's compile error" do
      code = """
      import Hologram.Query
      sort(Hologram.Test.Fixtures.Entity.Module2, :c)
      """

      assert_error Hologram.CompileError,
                   "nofile:2: sort names an attribute with a bare name, got: :c - write c",
                   fn -> Code.eval_string(code) end
    end
  end
end
