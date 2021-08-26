defmodule Hologram.Test.Helpers do
  alias Hologram.Compiler.Reflection
  alias Mix.Tasks.Compile.Hologram, as: Task

  @default_pages_path Reflection.pages_path()

  def compile_pages(pages_path \\ @default_pages_path) do
    Task.run(pages_path: pages_path)
  end
end
