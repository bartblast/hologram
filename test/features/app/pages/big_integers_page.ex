defmodule HologramFeatureTests.BigIntegersPage do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Components.BigIntegers.Todos
  alias HologramFeatureTests.Entities.Todo

  route "/big-integers"

  layout HologramFeatureTests.Components.DefaultLayout

  state :result, :string

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click={action: :create_big}> Create big </button>
      <button $click={action: :find_big}> Find big </button>
      <button $click={action: :move_big}> Move big </button>
    </p>
    <Todos cid="todos" />
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    """
  end

  def action(:create_big, _params, component) do
    {:ok, _todo} =
      %{title: "big", votes: 9_007_199_254_740_993}
      |> Todo.new()
      |> DB.create()

    put_state(component, :result, "created")
  end

  def action(:find_big, _params, component) do
    titles =
      Todo
      |> filter(votes: 9_007_199_254_740_993)
      |> DB.read()
      |> Enum.map_join(",", & &1.title)

    put_state(component, :result, "found_[#{titles}]")
  end

  def action(:move_big, _params, component) do
    Todo
    |> filter(title: "big")
    |> one()
    |> DB.read()
    |> increment(:votes, 2)
    |> DB.update!()

    put_state(component, :result, "moved")
  end
end
