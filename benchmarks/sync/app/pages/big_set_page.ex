defmodule HologramSyncBenchmark.BigSetPage do
  use Hologram.Page
  use Hologram.DB

  alias HologramSyncBenchmark.Entities.SetPost
  alias HologramSyncBenchmark.Entities.SetTag

  route "/big_set"

  layout HologramSyncBenchmark.Components.DefaultLayout

  # The big set case's clients greet with this page, which reads the tag and the posts they may see.
  derived :posts, [SetPost], fn -> sort(SetPost, position) end
  derived :tags, [SetTag], fn -> sort(SetTag, name) end

  def template do
    ~HOLO"""
    <p>{length(@tags)} tags, {length(@posts)} posts</p>
    """
  end
end
