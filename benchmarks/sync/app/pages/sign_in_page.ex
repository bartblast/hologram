defmodule HologramSyncBenchmark.SignInPage do
  use Hologram.Page

  route "/sign_in/:user_id"

  param :user_id, :string

  layout HologramSyncBenchmark.Components.DefaultLayout

  # Where a signed-in client gets its session cookie: the render signs it in as the user the
  # path names. The client then greets with its case's page, so this page's own windows only
  # decide which windows fill first, never what the client may read.
  def init(params, component, server) do
    {component, put_user_id(server, params.user_id)}
  end

  def template do
    ~HOLO"""
    <p>Signed in</p>
    """
  end
end
