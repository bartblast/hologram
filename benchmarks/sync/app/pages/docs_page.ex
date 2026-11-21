defmodule HologramSyncBenchmark.DocsPage do
  use Hologram.Page
  use Hologram.DB

  alias HologramSyncBenchmark.Entities.Doc

  route "/docs"

  layout HologramSyncBenchmark.Components.DefaultLayout

  # The access case's clients greet with this page, which reads every doc.
  derived :docs, [Doc], fn -> sort(Doc, position) end

  def template do
    ~HOLO"""
    <p>{length(@docs)} docs</p>
    """
  end
end
