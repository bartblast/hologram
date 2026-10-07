# The scenario on this page verifies that an action the server pushes waits for the chunks of the
# struct it carries, and holds nothing else up. The command queues two broadcasts to the page, the
# first with a struct no tab has met and the second with none. Realtime promises no order between
# them, and the second can run first while the first waits for its chunks, so the page keeps each
# one's result on its own. Client-reachable code on this page (template, actions) must not
# reference the struct fixture, otherwise the page preloads its chunks and the first action never
# waits.
defmodule HologramFeatureTests.CallGraph.PushedStructsPage do
  use Hologram.Page

  alias HologramFeatureTests.PushedStructFixture

  @channel :pushed_structs

  route "/call-graph/pushed-structs"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, server) do
    {
      put_state(component, plain_result: nil, struct_result: nil),
      put_subscription(server, @channel)
    }
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="push"> Push </button>
    </p>
    <p>
      Plain result: <strong id="plain-result">{@plain_result}</strong>
    </p>
    <p>
      Struct result: <strong id="struct-result">{@struct_result}</strong>
    </p>
    """
  end

  def action(:push, _params, component) do
    put_command(component, :push)
  end

  def action(:put_plain, params, component) do
    put_state(component, :plain_result, params.text)
  end

  def action(:put_struct, params, component) do
    put_state(component, :struct_result, params.struct)
  end

  def command(:push, _params, server) do
    server
    |> put_broadcast(@channel, :put_struct, struct: %PushedStructFixture{name: "pushed"})
    |> put_broadcast(@channel, :put_plain, text: "plain")
  end
end
