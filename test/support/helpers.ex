defmodule Hologram.Test.Helpers do
  alias Hologram.Compiler.{Context, Normalizer, Parser, Transformer}
  alias Hologram.Runtime.Reflection
  alias Mix.Tasks.Compile.Hologram, as: Task

  @default_pages_path Reflection.pages_path()

  def ast(code) do
    Parser.parse!(code)
    |> Normalizer.normalize()
  end

  def compile_pages(pages_path \\ @default_pages_path) do
    Task.run(pages_path: pages_path)
  end

  def ir(code) do
    ast(code)
    |> Transformer.transform(%Context{})
  end
end
