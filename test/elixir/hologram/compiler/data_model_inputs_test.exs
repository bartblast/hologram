defmodule Hologram.Compiler.DataModelInputsTest do
  use Hologram.Test.BasicCase, async: false
  import Hologram.Compiler.DataModelInputs

  alias Hologram.Commons.SerializationUtils
  alias Hologram.Compiler.CompileInputs
  alias Hologram.Reflection

  @test_dir Path.join([Reflection.tmp_dir(), "tests", "compiler", "data_model_inputs"])

  @build_lib_dir Path.join(@test_dir, "build_lib")
  @manifest_path Path.join([@build_lib_dir, "hologram", ".mix", "compile.elixir"])
  @manifest_dir Path.dirname(@manifest_path)

  setup_all do
    clean_dir(@test_dir)
    File.mkdir_p!(@manifest_dir)
    File.write!(@manifest_path, "manifest 1")

    [opts: [build_lib_dir: @build_lib_dir]]
  end

  describe "build/1" do
    test "digests the manifests", %{opts: opts} do
      assert build(opts) == %{manifests: CompileInputs.list_manifest_digests(@build_lib_dir)}
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
      record = build(opts)

      dump(record, path)

      assert load(path) == record
    end
  end

  describe "unchanged?/2" do
    setup %{opts: opts} do
      [record: build(opts)]
    end

    test "a manifest changed", %{opts: opts, record: record} do
      on_exit(fn -> File.write!(@manifest_path, "manifest 1") end)
      File.write!(@manifest_path, "manifest 2")

      refute unchanged?(record, opts)
    end

    test "a manifest vanished", %{opts: opts, record: record} do
      on_exit(fn -> File.write!(@manifest_path, "manifest 1") end)
      File.rm!(@manifest_path)

      refute unchanged?(record, opts)
    end

    test "nothing changed", %{opts: opts, record: record} do
      assert unchanged?(record, opts)
    end
  end
end
