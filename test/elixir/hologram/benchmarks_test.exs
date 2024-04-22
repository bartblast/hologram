defmodule Hologram.BenchmarksTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Benchmarks

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.IR

  test "build_ir_plt/1" do
    module_beam_path_plt = build_module_beam_path_plt()

    assert %PLT{} = plt = build_ir_plt(module_beam_path_plt)
    assert %IR.ModuleDefinition{} = PLT.get!(plt, Hologram.Benchmarks)
  end

  test "build_module_beam_path_plt/0" do
    assert %PLT{} = plt = build_module_beam_path_plt()
    assert PLT.get!(plt, Hologram.Benchmarks) == :code.which(Hologram.Benchmarks)
  end
end
