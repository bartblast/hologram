defmodule Hologram.Runtime.TemplateStoreTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.Reflection
  alias Hologram.Runtime.TemplateStore

  @path Reflection.root_template_store_path()

  # TODO: test explicitely
  test "populate_table/1" do
    store_content = %{key_1: :value_1, key_2: :value_2}
    @path |> Path.dirname() |> File.mkdir_p!()
    File.write!(@path, Utils.serialize(store_content))

    TemplateStore.run(path: @path)

    assert TemplateStore.get_all() == store_content
  end
end
