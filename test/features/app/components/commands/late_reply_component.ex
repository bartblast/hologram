defmodule HologramFeatureTests.Components.Commands.LateReplyComponent do
  use Hologram.Component

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  # Mounted on the late reply page only, so its cid is registered nowhere once the user has
  # navigated away. A reply that survives the navigation then has no target, and raises an
  # invalid action target error on the page navigated to.
  def init(_props, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click={command: :slow_component_command}>Run slow component command</button>
      Component result: <strong id="component_result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:record_component_reply, _params, component) do
    put_state(component, :result, "component_reply_ran")
  end

  # Stands in for a slow fetch: the reply is still in flight after the user has navigated away.
  def command(:slow_component_command, _params, server) do
    Process.sleep(3_000)
    put_action(server, :record_component_reply)
  end
end
