defmodule Hologram.Test.Helpers do
  alias Hologram.Compiler.Reflection
  alias Hologram.Utils
  alias Mix.Tasks.Compile.Hologram, as: Task

  @default_pages_path Reflection.pages_path()

  def compile_pages(pages_path \\ @default_pages_path) do
    Task.run(pages_path: pages_path)
  end

  defdelegate uuid_hex_regex, to: Utils
  defdelegate uuid_regex, to: Utils
end
