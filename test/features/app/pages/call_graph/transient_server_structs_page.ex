# The scenarios on this page verify that a struct server code builds and drops loads none of its
# chunks, while the structs server code puts in the state load theirs. A struct type's protocol
# implementations live in its chunks, which the server names when a struct of the type is on its
# way to the browser. Client-reachable code on this page (template, actions) must not reference
# the struct fixtures, otherwise the page preloads their chunks and the scenarios silently stop
# testing what the server code hands to the client.
defmodule HologramFeatureTests.CallGraph.TransientServerStructsPage do
  use Hologram.Page

  alias HologramFeatureTests.ReachedStructFixture
  alias HologramFeatureTests.TransientStructFixture

  route "/call-graph/transient-server-structs"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    {:ok, reached} = load(:reached)

    put_state(component,
      items: Enum.map([1, 2], fn count -> %ReachedStructFixture{name: "item #{count}"} end),
      label: "initial",
      reached: reached,
      transient_text: describe(%TransientStructFixture{name: "transient"})
    )
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="relabel"> Relabel </button>
    </p>
    <p>
      Label: <strong id="label">{@label}</strong>
    </p>
    <p>
      Transient text: <strong id="transient-text">{@transient_text}</strong>
    </p>
    <p>
      Reached: <strong id="reached">{@reached}</strong>
    </p>
    <p id="items">
      {%for item <- @items}<span>{item}</span>{/for}
    </p>
    """
  end

  def action(:relabel, _params, component) do
    put_state(component, :label, "relabeled")
  end

  # Runs the struct's String.Chars implementation on the server.
  defp describe(struct), do: "#{struct}"

  defp load(name), do: {:ok, %ReachedStructFixture{name: to_string(name)}}
end
