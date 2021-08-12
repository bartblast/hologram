defmodule Hologram.Test.Helpers do
  alias Hologram.Compiler.{Context, Normalizer, Parser, Transformer}
  alias Mix.Tasks.Compile.Hologram, as: Task

  def ast(code) do
    Parser.parse!(code)
    |> Normalizer.normalize()
  end

  def compile_pages(pages_path) do
    Task.run(pages_path: pages_path)
  end

  def ir(code) do
    ast(code)
    |> Transformer.transform(%Context{})
  end
end
