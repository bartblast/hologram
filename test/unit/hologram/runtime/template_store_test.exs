defmodule Hologram.Runtime.TemplateStoreTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.Reflection
  alias Hologram.Runtime.TemplateStore

  # TODO: test implicitely
  test "populate_table/1" do
    dump_path = Reflection.release_template_store_path()
    store_content = %{key_1: :value_1, key_2: :value_2}
    Path.dirname(dump_path) |> File.mkdir_p!()
    File.write!(dump_path, Utils.serialize(store_content))

    TemplateStore.run()

    assert TemplateStore.get_all() == store_content
  end
end
