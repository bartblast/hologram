defmodule HologramSyncBenchmark.SessionPage do
  use Hologram.Page

  route "/session"

  layout HologramSyncBenchmark.Components.DefaultLayout

  # Where an anonymous client gets its session cookie: a page with no data, so preparing
  # thousands of clients doesn't render a case's rows thousands of times. The client then greets
  # with its case's page.
  def template do
    ~HOLO"""
    <p>Session</p>
    """
  end
end
