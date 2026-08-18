defmodule HologramFeatureTests.JavaScriptInterop.PendingActionsSourcePage do
  use Hologram.Page

  alias Hologram.UI.Link
  alias HologramFeatureTests.JavaScriptInterop.PendingActionsPage

  route "/js-interop/pending-actions-source"

  layout HologramFeatureTests.Components.DefaultLayout

  # Reaching the pending-actions page through a link exercises the client-side path, where the
  # runtime is already up and the page's inline script calls the real dispatchAction rather than
  # the buffering shim a document load leaves in place.
  def template do
    ~HOLO"""
    <h1>Pending actions source page</h1>
    <Link to={PendingActionsPage}>Pending actions link</Link>
    """
  end
end
