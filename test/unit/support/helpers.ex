defmodule Hologram.Test.Helpers do
  alias Hologram.Compiler
  alias Hologram.Compiler.Reflection

  def compile(opts \\ []) do
    result =
      Keyword.put(opts, :force, true)
      |> Compiler.compile()

    # FIXME: for some reason using File.cp!/3 truncates the source file
    copy_template_store_dump_to_release_path()

    result
  end

  def md5_hex_regex do
    ~r/^[0-9a-f]{32}$/
  end

  defp copy_template_store_dump_to_release_path do
    dump_path = Reflection.root_template_store_path()
    release_path = Reflection.release_template_store_path()

    data = File.read!(dump_path)
    File.write!(release_path, data)
  end
end
