# Run in the project root dir:
# $ mix run benchmarks/elixir/support/generate_page_fixtures.exs

alias Hologram.Reflection

pages_dir =
  Path.join([
    Reflection.root_dir(),
    "benchmarks",
    "elixir",
    "support",
    "fixtures",
    "pages"
  ])

Enum.each(1..100, fn i ->
  content = """
  # credo:disable-for-this-file Credo.Check.Readability.Specs
  defmodule Hologram.Benchmarks.Fixtures.Page#{i} do
    @moduledoc false

    use Hologram.Page

    import Hologram.Commons.KernelUtils, only: [inspect: 1]
    import Kernel, except: [inspect: 1]

    route "/page-#{i}"

    layout Hologram.Benchmarks.Fixtures.Components.DefaultLayout

    @integer_c 345

    def init(_params, component, _server) do
      put_state(component,
        boolean_a: true,
        boolean_b: false,
        integer_a: 123,
        integer_b: 234,
        list_a: [1, 2, 3],
        list_b: [2, 3, 4],
        result: nil
      )
    end

    def template do
      ~HOLO\"""
      <p>
        <button id="unary+" $click={:"unary+", value: @integer_a}> unary + </button>
        <button id="unary-" $click={:"unary-", value: @integer_a}> unary - </button>
        <button id="+" $click={:+, left: @integer_a, right: @integer_b}> + </button>
        <button id="-" $click={:-, left: @integer_a, right: @integer_b}> - </button>
        <button id="*" $click={:*, left: @integer_a, right: @integer_b}> * </button>
        <button id="/" $click={:/, left: @integer_a, right: @integer_b}> / </button>
        <button id="++" $click={:++, left: @list_a, right: @list_b}> ++ </button>
        <button id="--" $click={:--, left: @list_a, right: @list_b}> -- </button>
        <button id="and" $click={:and, left: @boolean_a, right: @boolean_b}> and </button>
        <button id="&&" $click={:&&, left: @boolean_a, right: @boolean_b}> &amp;&amp; </button>
        <button id="or" $click={:or, left: @boolean_a, right: @boolean_b}> or </button>
        <button id="||" $click={:||, left: @boolean_a, right: @boolean_b}> || </button>
        <button id="not" $click={:not, value: @boolean_a}> not </button>
        <button id="!" $click={:!, value: @boolean_a}> ! </button>
        <button id="in" $click={:in, left: @integer_a, right: @list_a}> in </button>
        <button id="not in" $click={:"not in", left: @integer_a, right: @list_a}> not in </button>
        <button id="@" $click="@"> @ </button>
        <button id=".." $click={:.., left: @integer_a, right: @integer_b}> .. </button>
      </p>
      <p>
        Result: <strong id="result">{inspect(@result)}</strong>
      </p>
      \"\"\"
    end

    def action(:"unary+", %{value: value}, component) do
      put_state(component, :result, +value)
    end

    def action(:"unary-", %{value: value}, component) do
      put_state(component, :result, -value)
    end

    def action(:+, %{left: left, right: right}, component) do
      put_state(component, :result, left + right)
    end

    def action(:-, %{left: left, right: right}, component) do
      put_state(component, :result, left - right)
    end

    def action(:*, %{left: left, right: right}, component) do
      put_state(component, :result, left * right)
    end

    def action(:/, %{left: left, right: right}, component) do
      put_state(component, :result, left / right)
    end

    def action(:++, %{left: left, right: right}, component) do
      put_state(component, :result, left ++ right)
    end

    def action(:--, %{left: left, right: right}, component) do
      put_state(component, :result, left -- right)
    end

    def action(:and, %{left: left, right: right}, component) do
      put_state(component, :result, left and right)
    end

    def action(:&&, %{left: left, right: right}, component) do
      put_state(component, :result, left && right)
    end

    def action(:or, %{left: left, right: right}, component) do
      put_state(component, :result, left or right)
    end

    def action(:||, %{left: left, right: right}, component) do
      put_state(component, :result, left || right)
    end

    def action(:not, %{value: value}, component) do
      put_state(component, :result, not value)
    end

    def action(:!, %{value: value}, component) do
      put_state(component, :result, !value)
    end

    def action(:in, %{left: left, right: right}, component) do
      put_state(component, :result, left in right)
    end

    def action(:"not in", %{left: left, right: right}, component) do
      put_state(component, :result, left not in right)
    end

    def action(:@, _params, component) do
      put_state(component, :result, @integer_c)
    end

    def action(:.., %{left: left, right: right}, component) do
      put_state(component, :result, left..right)
    end
  end
  """

  pages_dir
  |> Path.join("page#{i}.ex")
  |> File.write!(content)
end)

# The pages whose client code reaches a registered query, so that what the data layer derives
# from the pages' reach has something to derive: both query components are rendered, and the
# entity type handed over is one the template names.
Enum.each(1..10, fn i ->
  content = """
  # credo:disable-for-this-file Credo.Check.Readability.Specs
  defmodule Hologram.Benchmarks.Fixtures.QueryPage#{i} do
    @moduledoc false

    use Hologram.Page

    alias Hologram.Benchmarks.Fixtures.Components.EntityPropComponent
    alias Hologram.Benchmarks.Fixtures.Components.QueryPropComponent
    alias Hologram.Benchmarks.Fixtures.Entity1

    route "/query-page-#{i}"

    layout Hologram.Benchmarks.Fixtures.Components.DefaultLayout

    def template do
      ~HOLO\"""
      <EntityPropComponent cid="entity_prop" entity={%Entity1{name: "entity", position: 1}} />
      <QueryPropComponent cid="query_prop" min_position={1} />
      \"\"\"
    end
  end
  """

  pages_dir
  |> Path.join("query_page#{i}.ex")
  |> File.write!(content)
end)
