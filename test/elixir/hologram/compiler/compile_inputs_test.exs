defmodule Hologram.Compiler.CompileInputsTest do
  use Hologram.Test.BasicCase, async: false
  import Hologram.Compiler.CompileInputs

  alias Hologram.Commons.SerializationUtils
  alias Hologram.Compiler
  alias Hologram.Reflection

  @test_dir Path.join([Reflection.tmp_dir(), "tests", "compiler", "compile_inputs"])

  @assets_dir Path.join(@test_dir, "assets")
  @build_lib_dir Path.join(@test_dir, "build_lib")
  @js_dir Path.join(@assets_dir, "js")
  @manifest_path Path.join([@build_lib_dir, "hologram", ".mix", "compile.elixir"])
  @static_dir Path.join(@test_dir, "static")

  @lib_assets_dir Path.join(Reflection.root_dir(), "assets")
  @lib_js_dir Path.join(@lib_assets_dir, "js")
  @lib_package_json_path Path.join(@lib_assets_dir, "package.json")

  @imported_js_path Path.join(@test_dir, "imported.mjs")
  @manifest_dir Path.dirname(@manifest_path)
  @static_file_path Path.join(@static_dir, "page-Module1-ABC.js")
  @package_json_path Path.join(@assets_dir, "package.json")

  setup_all do
    clean_dir(@test_dir)
    File.mkdir_p!(@assets_dir)
    File.mkdir_p!(@manifest_dir)
    File.mkdir_p!(@static_dir)

    File.cp_r!(@lib_js_dir, @js_dir)
    File.cp!(@lib_package_json_path, @package_json_path)

    File.write!(@imported_js_path, "export const a = 1;\n")
    File.write!(@manifest_path, "manifest 1")

    for file_name <- ["page-Module2-DEF.js", "page-Module1-ABC.js"] do
      @static_dir
      |> Path.join(file_name)
      |> File.write!("")
    end

    opts = [
      assets_dir: @assets_dir,
      build_lib_dir: @build_lib_dir,
      js_dir: @js_dir,
      static_dir: @static_dir
    ]

    [opts: opts]
  end

  describe "build/1" do
    test "digests the manifest of every loaded application that has one", %{opts: opts} do
      assert build(opts).manifests == [{:hologram, :erlang.phash2("manifest 1")}]
    end

    test "lists no static file when the static dir is missing", %{opts: opts} do
      missing_static_dir = Path.join(@test_dir, "missing")
      missing_static_dir_opts = Keyword.put(opts, :static_dir, missing_static_dir)

      assert build(missing_static_dir_opts).static_files == []
    end

    test "lists the static files in name order", %{opts: opts} do
      assert build(opts).static_files == ["page-Module1-ABC.js", "page-Module2-DEF.js"]
    end

    test "names the bundle inputs that need no module", %{opts: opts} do
      assert build(opts).bundle_inputs == Compiler.build_bundle_inputs(opts)
    end

    test "names the client config", %{opts: opts} do
      assert build(opts).client_config == Compiler.client_config()
    end
  end

  describe "dump/2 and load/1" do
    test "a record of another version is not loaded" do
      path = Path.join(@test_dir, "other_version.bin")
      File.write!(path, SerializationUtils.serialize({0, %{}}))

      assert load(path) == nil
    end

    test "no record" do
      assert load(Path.join(@test_dir, "none.bin")) == nil
    end

    test "round trip", %{opts: opts} do
      path = Path.join(@test_dir, "round_trip.bin")

      record =
        opts
        |> build()
        |> Map.put(:js_inputs, %{"/app/assets/js/hooks.mjs" => {:digest, 123}})

      dump(record, path)

      assert load(path) == record
    end
  end

  describe "unchanged?/2" do
    setup %{opts: opts} do
      js_inputs = Compiler.fingerprint_js_inputs([@imported_js_path], nil)

      record =
        opts
        |> build()
        |> Map.put(:js_inputs, js_inputs)

      [record: record]
    end

    test "a JavaScript file recorded as fresh", %{opts: opts, record: record} do
      fresh_record = %{record | js_inputs: %{@imported_js_path => :fresh}}

      refute unchanged?(fresh_record, opts)
    end

    test "a manifest changed", %{opts: opts, record: record} do
      on_exit(fn -> File.write!(@manifest_path, "manifest 1") end)
      File.write!(@manifest_path, "manifest 2")

      refute unchanged?(record, opts)
    end

    test "a static file vanished", %{opts: opts, record: record} do
      on_exit(fn -> File.write!(@static_file_path, "") end)
      File.rm!(@static_file_path)

      refute unchanged?(record, opts)
    end

    test "an imported JavaScript file changed", %{opts: opts, record: record} do
      on_exit(fn -> File.write!(@imported_js_path, "export const a = 1;\n") end)
      File.write!(@imported_js_path, "export const a = 2;\n")

      refute unchanged?(record, opts)
    end

    test "nothing changed", %{opts: opts, record: record} do
      assert unchanged?(record, opts)
    end

    test "the client stack traces setting changed", %{opts: opts, record: record} do
      on_exit(fn -> Application.delete_env(:hologram, :client_stacktraces) end)
      Application.put_env(:hologram, :client_stacktraces, not Hologram.client_stacktraces?())

      refute unchanged?(record, opts)
    end
  end
end
