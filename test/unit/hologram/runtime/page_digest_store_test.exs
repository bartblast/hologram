defmodule Hologram.Runtime.PageDigestStoreTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.Reflection
  alias Hologram.Runtime.PageDigestStore

  test "populate_table/1" do
    dump_path = Reflection.release_page_digest_store_path()
    store_content = %{key_1: :value_1, key_2: :value_2}
    Path.dirname(dump_path) |> File.mkdir_p!()
    File.write!(dump_path, Utils.serialize(store_content))

    PageDigestStore.run()

    assert PageDigestStore.get_all() == store_content
  end
end
