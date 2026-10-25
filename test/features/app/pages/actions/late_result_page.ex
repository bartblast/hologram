defmodule HologramFeatureTests.Actions.LateResultPage do
  use Hologram.Page
  use Hologram.JS

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias Hologram.UI.Link
  alias HologramFeatureTests.Actions.LateResultDestinationPage
  alias HologramFeatureTests.Actions.Page21
  alias HologramFeatureTests.Components.Actions.LateResultComponent

  js_import from: "./helpers.mjs", as: :helpers

  route "/actions/late-result"

  layout HologramFeatureTests.Components.LateResultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <h1>Late result title</h1>
    <LateResultComponent cid="late_result_component" />
    <p>
      Page result: <strong id="page_result"><code>{inspect(@result)}</code></strong>
    </p>
    <p>
      <button $click={action: :slow_layout_action, target: "layout"}>Run slow layout action</button>
      <button $click="slow_page_action">Run slow page action</button>
      <button $click="slow_command_action">Run slow command action</button>
      <button $click="slow_navigating_action">Run slow navigating action</button>
    </p>
    <Link to={LateResultDestinationPage}>Destination link</Link>
    """
  end

  # Each slow action stands in for a slow fetch: the await is still pending after the user has
  # navigated away, and what follows it is the part of the result under test.

  # The destination has the same :result key and renders it, so a surviving write shows there.
  def action(:slow_page_action, _params, component) do
    :helpers
    |> JS.call(:slowValue, [3000])
    |> Task.await()

    put_state(component, :result, "page_result_ran")
  end

  # The destination defines no command, so a surviving command fails on the server and the client
  # raises on the failed reply.
  def action(:slow_command_action, _params, component) do
    :helpers
    |> JS.call(:slowValue, [3000])
    |> Task.await()

    put_command(component, :record_page_command)
  end

  # Any page other than the destination would do. A surviving navigation pulls the user off the
  # page they chose.
  def action(:slow_navigating_action, _params, component) do
    :helpers
    |> JS.call(:slowValue, [3000])
    |> Task.await()

    put_page(component, Page21)
  end

  def action(:record_page_command_reply, _params, component) do
    put_state(component, :result, "page_command_ran")
  end

  def command(:record_page_command, _params, server) do
    put_action(server, :record_page_command_reply)
  end
end
