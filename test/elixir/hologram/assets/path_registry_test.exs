defmodule Hologram.Assets.PathRegistryTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Assets.PathRegistry
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
  alias Hologram.Commons.ETS

  use_module_stub :asset_path_registry

  setup :set_mox_global

  setup do
    setup_asset_path_registry(AssetPathRegistryStub, false)
  end

  # Puts the env var back as it was before the test, set or not.
  defp put_hologram_env(env) do
    previous = System.get_env("HOLOGRAM_ENV")

    on_exit(fn ->
      if previous do
        System.put_env("HOLOGRAM_ENV", previous)
      else
        System.delete_env("HOLOGRAM_ENV")
      end
    end)

    System.put_env("HOLOGRAM_ENV", env)
  end

  defp write_cache_manifest(json) do
    write_static_file("cache_manifest.json", json)
  end

  defp write_static_file(relative_path, content) do
    file_path = Path.join(AssetPathRegistryStub.static_dir(), relative_path)

    file_path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(file_path, content)
  end

  test "get_mapping/0", %{mapping: mapping} do
    AssetPathRegistry.start_link([])
    assert get_mapping() == mapping
  end

  describe "handle_call/3" do
    test "get_mapping", %{mapping: mapping} do
      AssetPathRegistry.start_link([])
      process_name = AssetPathRegistryStub.process_name()

      assert GenServer.call(process_name, :get_mapping) == mapping
    end
  end

  describe "init/1" do
    test "fills the ETS table with the mapping of the static dir", %{mapping: mapping} do
      ets_table_name = AssetPathRegistryStub.ets_table_name()

      assert init(nil) == {:ok, nil}
      assert ets_table_exists?(ets_table_name)
      assert ETS.get_all(ets_table_name) == mapping
    end

    test "picks the plain file over a copy that no longer holds its content in dev and test" do
      write_static_file("test_dir_3/test_file_12.css", "new content")

      write_static_file(
        "test_dir_3/test_file_12-0f5f13cf0b14c88bd431ef163b63d68d.css",
        "old content"
      )

      init(nil)

      assert lookup("test_dir_3/test_file_12.css") == {:ok, "/test_dir_3/test_file_12.css"}
      assert lookup("test_dir_3/test_file_12-0f5f13cf0b14c88bd431ef163b63d68d.css") == :error
    end

    test "picks a copy that holds the content of the file at its key in dev and test" do
      write_static_file("test_dir_3/test_file_12.css", "new content")

      write_static_file(
        "test_dir_3/test_file_12-96c15c2bb2921193bf290df8cd85e2ba.css",
        "new content"
      )

      init(nil)

      assert lookup("test_dir_3/test_file_12.css") ==
               {:ok, "/test_dir_3/test_file_12-96c15c2bb2921193bf290df8cd85e2ba.css"}
    end

    test "picks the copy that holds the content of the file at its key over a stale one that sorts after it in dev and test" do
      write_static_file("test_dir_3/test_file_12.css", "new content")

      write_static_file(
        "test_dir_3/test_file_12-96c15c2bb2921193bf290df8cd85e2ba.css",
        "new content"
      )

      write_static_file(
        "test_dir_3/test_file_12-ffffffffffffffffffffffffffffffff.css",
        "old content"
      )

      init(nil)

      assert lookup("test_dir_3/test_file_12.css") ==
               {:ok, "/test_dir_3/test_file_12-96c15c2bb2921193bf290df8cd85e2ba.css"}
    end

    test "serves each copy under its own name when nothing is at its key in dev and test" do
      write_static_file(
        "test_dir_3/test_file_12-0f5f13cf0b14c88bd431ef163b63d68d.css",
        "old content"
      )

      write_static_file(
        "test_dir_3/test_file_12-96c15c2bb2921193bf290df8cd85e2ba.css",
        "new content"
      )

      init(nil)

      assert lookup("test_dir_3/test_file_12.css") == :error

      assert lookup("test_dir_3/test_file_12-0f5f13cf0b14c88bd431ef163b63d68d.css") ==
               {:ok, "/test_dir_3/test_file_12-0f5f13cf0b14c88bd431ef163b63d68d.css"}

      assert lookup("test_dir_3/test_file_12-96c15c2bb2921193bf290df8cd85e2ba.css") ==
               {:ok, "/test_dir_3/test_file_12-96c15c2bb2921193bf290df8cd85e2ba.css"}
    end

    test "picks the copy the cache manifest names as the latest outside dev and test" do
      put_hologram_env("prod")

      write_static_file("test_dir_3/test_file_12.css", "new content")

      write_static_file(
        "test_dir_3/test_file_12-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.css",
        "old content"
      )

      write_static_file(
        "test_dir_3/test_file_12-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.css",
        "older content"
      )

      write_cache_manifest(~S"""
      {"latest": {"test_dir_3/test_file_12.css": "test_dir_3/test_file_12-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.css"}}
      """)

      init(nil)

      assert lookup("test_dir_3/test_file_12.css") ==
               {:ok, "/test_dir_3/test_file_12-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.css"}
    end

    test "picks the copy the cache manifest names as the latest when nothing is at its key outside dev and test" do
      put_hologram_env("prod")

      write_static_file(
        "test_dir_3/test_file_12-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.css",
        "old content"
      )

      write_cache_manifest(~S"""
      {"latest": {"test_dir_3/test_file_12.css": "test_dir_3/test_file_12-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.css"}}
      """)

      init(nil)

      assert lookup("test_dir_3/test_file_12.css") ==
               {:ok, "/test_dir_3/test_file_12-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.css"}
    end

    test "picks the plain file when the cache manifest names no copy for it outside dev and test" do
      put_hologram_env("prod")

      write_static_file("test_dir_3/test_file_12.css", "new content")

      write_static_file(
        "test_dir_3/test_file_12-96c15c2bb2921193bf290df8cd85e2ba.css",
        "new content"
      )

      write_cache_manifest(~S({"latest": {}}))

      init(nil)

      assert lookup("test_dir_3/test_file_12.css") == {:ok, "/test_dir_3/test_file_12.css"}
      assert lookup("test_dir_3/test_file_12-96c15c2bb2921193bf290df8cd85e2ba.css") == :error
    end

    test "picks the plain file when there is no cache manifest outside dev and test" do
      put_hologram_env("prod")

      write_static_file("test_dir_3/test_file_12.css", "new content")

      write_static_file(
        "test_dir_3/test_file_12-96c15c2bb2921193bf290df8cd85e2ba.css",
        "new content"
      )

      init(nil)

      assert lookup("test_dir_3/test_file_12.css") == {:ok, "/test_dir_3/test_file_12.css"}
    end

    test "picks the plain file when the cache manifest isn't valid JSON outside dev and test" do
      put_hologram_env("prod")

      write_static_file("test_dir_3/test_file_12.css", "new content")

      write_static_file(
        "test_dir_3/test_file_12-96c15c2bb2921193bf290df8cd85e2ba.css",
        "new content"
      )

      write_cache_manifest("{")

      init(nil)

      assert lookup("test_dir_3/test_file_12.css") == {:ok, "/test_dir_3/test_file_12.css"}
    end

    test "picks the plain file when the cache manifest has no latest map outside dev and test" do
      put_hologram_env("prod")

      write_static_file("test_dir_3/test_file_12.css", "new content")

      write_static_file(
        "test_dir_3/test_file_12-96c15c2bb2921193bf290df8cd85e2ba.css",
        "new content"
      )

      write_cache_manifest(~S({"version": 1}))

      init(nil)

      assert lookup("test_dir_3/test_file_12.css") == {:ok, "/test_dir_3/test_file_12.css"}
    end

    test "serves each copy under its own name when the cache manifest names none and nothing is at its key outside dev and test" do
      put_hologram_env("prod")

      write_static_file(
        "test_dir_3/test_file_12-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.css",
        "old content"
      )

      write_cache_manifest(~S({"latest": {}}))

      init(nil)

      assert lookup("test_dir_3/test_file_12.css") == :error

      assert lookup("test_dir_3/test_file_12-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.css") ==
               {:ok, "/test_dir_3/test_file_12-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.css"}
    end

    test "reads a digested copy of a bundle as a copy, leaving the bundle's own key alone in dev and test" do
      write_static_file("hologram/runtime-AAAAAAAA-d41d8cd98f00b204e9800998ecf8427e.js", "")

      init(nil)

      assert lookup("hologram/runtime.js") == {:ok, "/hologram/runtime-AAAAAAAA.js"}

      assert lookup("hologram/runtime-AAAAAAAA.js") ==
               {:ok, "/hologram/runtime-AAAAAAAA-d41d8cd98f00b204e9800998ecf8427e.js"}
    end

    test "maps a bundle as in dev and test outside them" do
      put_hologram_env("prod")

      init(nil)

      assert lookup("hologram/runtime.js") == {:ok, "/hologram/runtime-AAAAAAAA.js"}
    end
  end

  describe "lookup/2" do
    setup do
      AssetPathRegistry.start_link([])
      :ok
    end

    test "asset exists, has digest suffix" do
      assert lookup("test_dir_1/test_dir_2/test_file_1.css") ==
               {:ok, "/test_dir_1/test_dir_2/test_file_1-d41d8cd98f00b204e9800998ecf8427e.css"}
    end

    test "asset exists, has esbuild content hash suffix, in hologram dir" do
      assert lookup("hologram/runtime.js") == {:ok, "/hologram/runtime-AAAAAAAA.js"}
    end

    test "asset exists, has esbuild content hash-like suffix, outside hologram dir" do
      assert lookup("test_dir_3/test_file_11-DOWNLOAD.css") ==
               {:ok, "/test_dir_3/test_file_11-DOWNLOAD.css"}

      assert lookup("test_dir_3/test_file_11.css") == :error
    end

    test "asset exists, doesn't have digest suffix" do
      assert lookup("test_dir_3/test_file_10.css") ==
               {:ok, "/test_dir_3/test_file_10.css"}
    end

    test "asset doesn't exist" do
      assert lookup("invalid_file.css") == :error
    end

    test "chunk bundle named by esbuild" do
      assert lookup("hologram/chunk.js") == :error
      assert lookup("hologram/chunk-DDDDDDDD.js") == :error
    end

    test "page bundle named by esbuild" do
      assert lookup("hologram/page-Elixir.MyPage1.js") == :error
      assert lookup("hologram/page-Elixir.MyPage1-BBBBBBBB.js") == :error
    end
  end

  test "register/2" do
    AssetPathRegistry.start_link([])
    AssetPathRegistry.register("my_static_path", "/my_asset_path")

    assert lookup("my_static_path") == {:ok, "/my_asset_path"}
  end

  describe "reload/0" do
    setup do
      AssetPathRegistry.start_link([])
      :ok
    end

    test "replaces a stale value of a bundle", %{mapping: mapping} do
      ets_table_name = AssetPathRegistryStub.ets_table_name()
      ETS.put(ets_table_name, "hologram/runtime.js", "/stale")

      reload()

      assert ETS.get_all(ets_table_name) == mapping
    end

    test "picks up a new runtime bundle" do
      static_dir = AssetPathRegistryStub.static_dir()
      File.rm!(static_dir <> "/hologram/runtime-AAAAAAAA.js")
      write_static_file("hologram/runtime-EEEEEEEE.js", "")

      reload()

      assert lookup("hologram/runtime.js") == {:ok, "/hologram/runtime-EEEEEEEE.js"}
    end

    test "leaves a key that isn't a static path alone" do
      ets_table_name = AssetPathRegistryStub.ets_table_name()
      ETS.put(ets_table_name, :dummy_key, :dummy_value)

      reload()

      assert ETS.get(ets_table_name, :dummy_key) == {:ok, :dummy_value}
    end

    test "leaves the entries of the app's assets alone" do
      ets_table_name = AssetPathRegistryStub.ets_table_name()
      ETS.put(ets_table_name, "test_dir_3/test_file_10.css", "/kept")
      write_static_file("test_dir_3/test_file_12.css", "new content")

      reload()

      assert lookup("test_dir_3/test_file_10.css") == {:ok, "/kept"}
      assert lookup("test_dir_3/test_file_12.css") == :error
    end

    test "removes a bundle key the static dir no longer holds", %{mapping: mapping} do
      ets_table_name = AssetPathRegistryStub.ets_table_name()
      ETS.put(ets_table_name, "hologram/stale.js", "/hologram/stale-EEEEEEEE.js")

      reload()

      assert ETS.get_all(ets_table_name) == mapping
    end
  end

  describe "update/1" do
    setup do
      AssetPathRegistry.start_link([])
      :ok
    end

    test "drops a copy that no longer holds the content of the changed file at its key" do
      write_static_file("test_dir_3/test_file_12.css", "new content")

      write_static_file(
        "test_dir_3/test_file_12-96c15c2bb2921193bf290df8cd85e2ba.css",
        "new content"
      )

      update(["test_dir_3/test_file_12.css"])

      write_static_file("test_dir_3/test_file_12.css", "old content")
      update(["test_dir_3/test_file_12.css"])

      assert lookup("test_dir_3/test_file_12.css") == {:ok, "/test_dir_3/test_file_12.css"}
    end

    test "picks up a new copy that holds the content of the file at its key" do
      write_static_file("test_dir_3/test_file_12.css", "new content")
      update(["test_dir_3/test_file_12.css"])

      write_static_file(
        "test_dir_3/test_file_12-96c15c2bb2921193bf290df8cd85e2ba.css",
        "new content"
      )

      update(["test_dir_3/test_file_12-96c15c2bb2921193bf290df8cd85e2ba.css"])

      assert lookup("test_dir_3/test_file_12.css") ==
               {:ok, "/test_dir_3/test_file_12-96c15c2bb2921193bf290df8cd85e2ba.css"}
    end

    test "adds a new file" do
      write_static_file("test_dir_3/test_file_12.css", "new content")

      update(["test_dir_3/test_file_12.css"])

      assert lookup("test_dir_3/test_file_12.css") == {:ok, "/test_dir_3/test_file_12.css"}
    end

    test "removes the key of a deleted file" do
      File.rm!(AssetPathRegistryStub.static_dir() <> "/test_dir_3/test_file_10.css")

      update(["test_dir_3/test_file_10.css"])

      assert lookup("test_dir_3/test_file_10.css") == :error
    end

    test "serves each copy under its own name once the file at its key is deleted" do
      write_static_file("test_dir_3/test_file_12.css", "new content")

      write_static_file(
        "test_dir_3/test_file_12-96c15c2bb2921193bf290df8cd85e2ba.css",
        "new content"
      )

      update(["test_dir_3/test_file_12.css"])

      File.rm!(AssetPathRegistryStub.static_dir() <> "/test_dir_3/test_file_12.css")
      update(["test_dir_3/test_file_12.css"])

      assert lookup("test_dir_3/test_file_12.css") == :error

      assert lookup("test_dir_3/test_file_12-96c15c2bb2921193bf290df8cd85e2ba.css") ==
               {:ok, "/test_dir_3/test_file_12-96c15c2bb2921193bf290df8cd85e2ba.css"}
    end

    test "removes the key of a copy served under its own name once it is deleted" do
      write_static_file(
        "test_dir_3/test_file_12-96c15c2bb2921193bf290df8cd85e2ba.css",
        "new content"
      )

      update(["test_dir_3/test_file_12-96c15c2bb2921193bf290df8cd85e2ba.css"])

      File.rm!(
        AssetPathRegistryStub.static_dir() <>
          "/test_dir_3/test_file_12-96c15c2bb2921193bf290df8cd85e2ba.css"
      )

      update(["test_dir_3/test_file_12-96c15c2bb2921193bf290df8cd85e2ba.css"])

      assert lookup("test_dir_3/test_file_12-96c15c2bb2921193bf290df8cd85e2ba.css") == :error
    end

    test "drops the copies served under their own names once a file is at their key again" do
      write_static_file(
        "test_dir_3/test_file_12-0f5f13cf0b14c88bd431ef163b63d68d.css",
        "old content"
      )

      update(["test_dir_3/test_file_12-0f5f13cf0b14c88bd431ef163b63d68d.css"])

      write_static_file("test_dir_3/test_file_12.css", "new content")
      update(["test_dir_3/test_file_12.css"])

      assert lookup("test_dir_3/test_file_12.css") == {:ok, "/test_dir_3/test_file_12.css"}
      assert lookup("test_dir_3/test_file_12-0f5f13cf0b14c88bd431ef163b63d68d.css") == :error
    end

    test "removes the keys of the files in a deleted dir", %{mapping: mapping} do
      File.rm_rf!(AssetPathRegistryStub.static_dir() <> "/test_dir_3")

      update(["test_dir_3"])

      test_dir_3_keys =
        mapping
        |> Map.keys()
        |> Enum.filter(&String.starts_with?(&1, "test_dir_3/"))

      assert ETS.get_all(AssetPathRegistryStub.ets_table_name()) ==
               Map.drop(mapping, test_dir_3_keys)
    end

    test "rebuilds every entry outside the hologram dir for the static dir itself" do
      ets_table_name = AssetPathRegistryStub.ets_table_name()
      ETS.put(ets_table_name, "test_dir_3/test_file_10.css", "/stale")
      ETS.put(ets_table_name, "hologram/runtime.js", "/kept")
      write_static_file("test_dir_4/test_file_12.css", "new content")

      update([""])

      assert lookup("test_dir_3/test_file_10.css") == {:ok, "/test_dir_3/test_file_10.css"}
      assert lookup("test_dir_4/test_file_12.css") == {:ok, "/test_dir_4/test_file_12.css"}
      assert lookup("hologram/runtime.js") == {:ok, "/kept"}
    end

    test "leaves out a link to nothing" do
      File.ln_s!(
        "missing.css",
        AssetPathRegistryStub.static_dir() <> "/test_dir_3/test_file_12.css"
      )

      update(["test_dir_3/test_file_12.css"])

      assert lookup("test_dir_3/test_file_12.css") == :error
    end

    test "adds the files of a new dir" do
      write_static_file("test_dir_4/test_file_12.css", "new content")

      update(["test_dir_4"])

      assert lookup("test_dir_4/test_file_12.css") == {:ok, "/test_dir_4/test_file_12.css"}
    end

    test "leaves the entries of unchanged files alone" do
      ets_table_name = AssetPathRegistryStub.ets_table_name()
      ETS.put(ets_table_name, "test_dir_3/test_file_10.css", "/kept")
      write_static_file("test_dir_3/test_file_12.css", "new content")

      update(["test_dir_3/test_file_12.css"])

      assert lookup("test_dir_3/test_file_10.css") == {:ok, "/kept"}
    end
  end

  test "start_link/1" do
    assert {:ok, pid} = AssetPathRegistry.start_link([])
    assert is_pid(pid)
    assert process_name_registered?(AssetPathRegistryStub.process_name())
    assert ets_table_exists?(AssetPathRegistryStub.ets_table_name())
  end
end
