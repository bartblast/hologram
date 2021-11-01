defmodule Hologram.Test.Helpers do
  alias Hologram.Compiler.Reflection
  alias Mix.Tasks.Compile.Hologram, as: Task

  @default_pages_path Reflection.pages_path()

  # When compile_pages/1 test helper is used, the router is recompiled with the pages found in the given pages_path.
  # After the tests, the router needs to be recompiled with the default pages_path.
  # Also, in such case the tests need to be non-async.
  def compile_pages(pages_path \\ @default_pages_path) do
    Task.run(pages_path: pages_path)
  end

  def has_edge?(graph, from_vertex, to_vertex) do
    edges = Graph.edges(graph, from_vertex, to_vertex)
    Enum.count(edges) == 1
  end
end
