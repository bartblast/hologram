defmodule HologramFeatureTests.Commands.LateReplyPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias Hologram.UI.Link
  alias HologramFeatureTests.Commands.LateReplyDestinationPage
  alias HologramFeatureTests.Components.Commands.LateReplyComponent

  route "/commands/late-reply"

  layout HologramFeatureTests.Components.LateReplyLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <h1>Late reply title</h1>
    <LateReplyComponent cid="late_reply_component" />
    <p>
      Page result: <strong id="page_result"><code>{inspect(@result)}</code></strong>
    </p>
    <p>
      <button $click={command: :slow_layout_command, target: "layout"}>Run slow layout command</button>
      <button $click={command: :slow_page_command}>Run slow page command</button>
    </p>
    <Link to={LateReplyDestinationPage}>Destination link</Link>
    """
  end

  # The destination deliberately defines no action, so a reply that outlives the navigation lands
  # on a module that cannot answer it.
  def action(:record_page_reply, _params, component) do
    put_state(component, :result, "page_reply_ran")
  end

  # Stands in for a slow fetch: the reply is still in flight after the user has navigated away.
  def command(:slow_page_command, _params, server) do
    Process.sleep(3_000)
    put_action(server, :record_page_reply)
  end
end
