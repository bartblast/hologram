defmodule Mix.Tasks.Compile.HologramTest do
  use Hologram.Test.BasicCase, async: true
  import Mix.Tasks.Compile.Hologram
  alias Hologram.Compiler.Reflection

  @root_path Reflection.root_path()
  @tmp_path "#{Reflection.tmp_path()}/#{__MODULE__}.run.1"

  setup do
    clean_dir(@tmp_path)
    :ok
  end

  test "run/1" do
    opts = [
      build_dir: @tmp_path,
      bundle_dir: @tmp_path,
      esbuild_path: "#{@root_path}/assets/node_modules/.bin/esbuild",
      js_source_dir: "#{@root_path}/assets/js"
    ]

    run(opts)
  end
end
