defmodule HologramFeatureTests.Commands.LateReplyDestinationPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias Hologram.UI.Link
  alias HologramFeatureTests.Commands.LateReplyPage

  route "/commands/late-reply-destination"

  layout HologramFeatureTests.Components.LateReplyLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <h1 id="destination_title">Late reply destination title</h1>
    <button $click={command: :destination_command}>Run destination command</button>
    <p>
      Destination result: <strong id="destination_result"><code>{inspect(@result)}</code></strong>
    </p>
    <Link to={LateReplyPage}>Late reply link</Link>
    """
  end

  def action(:record_destination_reply, _params, component) do
    put_state(component, :result, "destination_reply_ran")
  end

  # Clicked before this page has mounted, the command used to be built from the registry of the
  # page being left, whose page module has no clause for it. Held for the mount, it is built from
  # this page's.
  def command(:destination_command, _params, server) do
    put_action(server, :record_destination_reply)
  end
end
