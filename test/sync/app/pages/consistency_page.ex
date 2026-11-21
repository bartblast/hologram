defmodule HologramSyncTests.ConsistencyPage do
  use Hologram.Page

  alias HologramSyncTests.Components.ConsistencyLists

  route "/consistency/:user_id"

  param :user_id, :string

  layout HologramSyncTests.Components.DefaultLayout

  # The app has no sign-in of its own, so the page signs its session in as the user its path names.
  # A simulated client takes its session cookie from here, and syncs as that user.
  def init(params, _component, server) do
    put_user_id(server, params.user_id)
  end

  def template do
    ~HOLO"""
    <ConsistencyLists cid="consistency_lists" />
    """
  end
end
