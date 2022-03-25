defmodule HologramE2E.Test.Helpers do
  alias Hologram.Compiler.Reflection

  @default_app_path Reflection.app_path()

  def compile(opts \\ []) do
    Mix.Tasks.Compile.Hologram.run(opts)
  end
end
