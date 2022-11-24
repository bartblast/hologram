defmodule Hologram.Test.Helpers do
  alias Hologram.Compiler
  alias Hologram.Compiler.Reflection
  alias Hologram.Runtime

  def compile(opts \\ []) do
    Keyword.put(opts, :force, true)
    |> Compiler.compile()
  end

  def md5_hex_regex do
    ~r/^[0-9a-f]{32}$/
  end

  def run_runtime do
    [
      page_digest_store_path: Reflection.root_page_digest_store_path(),
      template_store_path: Reflection.root_template_store_path()
    ]
    |> Runtime.run()
  end
end
