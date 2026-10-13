defmodule Hologram.Test.HelpersTest do
  use Hologram.Test.BasicCase, async: true

  alias Hologram.Commons.CryptographicUtils
  alias Hologram.Reflection

  @lib_assets_dir Path.join(Reflection.root_dir(), "assets")
  @test_dir Path.join([Reflection.tmp_dir(), "tests", "support", "helpers"])

  describe "link_lib_js_deps/2" do
    setup do
      test_dir = Path.join(@test_dir, "link_lib_js_deps")
      clean_dir(test_dir)

      [assets_dir: Path.join(test_dir, "assets"), build_dir: Path.join(test_dir, "build")]
    end

    test "copies package.json and package-lock.json from the lib's assets dir", %{
      assets_dir: assets_dir,
      build_dir: build_dir
    } do
      link_lib_js_deps(assets_dir, build_dir)

      for file_name <- ["package.json", "package-lock.json"] do
        file_path = Path.join(assets_dir, file_name)
        lib_file_path = Path.join(@lib_assets_dir, file_name)
        assert File.read!(file_path) == File.read!(lib_file_path)
      end
    end

    test "writes the digest of package.json into the build dir", %{
      assets_dir: assets_dir,
      build_dir: build_dir
    } do
      link_lib_js_deps(assets_dir, build_dir)

      expected_digest =
        @lib_assets_dir
        |> Path.join("package.json")
        |> File.read!()
        |> CryptographicUtils.digest(:sha256, :binary)

      package_json_digest_path = Path.join(build_dir, "package_json_digest.bin")
      assert File.read!(package_json_digest_path) == expected_digest
    end

    test "returns the lib's node_modules path, with esbuild in it", %{
      assets_dir: assets_dir,
      build_dir: build_dir
    } do
      node_modules_path = link_lib_js_deps(assets_dir, build_dir)

      assert node_modules_path == Path.join(@lib_assets_dir, "node_modules")

      esbuild_bin_path = Path.join([node_modules_path, ".bin", "esbuild"])
      assert File.exists?(esbuild_bin_path)
    end
  end
end
