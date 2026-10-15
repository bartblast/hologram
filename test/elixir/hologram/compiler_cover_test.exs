defmodule Hologram.CompilerCoverTest do
  # async: false - cover-compiling a module changes how every concurrent test
  # resolves its beam, so the covered window must not overlap other tests.
  use Hologram.Test.BasicCase, async: false

  import Hologram.Compiler

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.IR
  alias Hologram.Test.Fixtures.Compiler.Module1

  describe "build_missing_ir!/2" do
    test "builds a cover-compiled module from its beam on disk" do
      # Stop the cover server only when this test started it - an externally
      # started server (mix test --cover) owns its lifecycle and data.
      case :cover.start() do
        {:ok, _pid} -> on_exit(fn -> :cover.stop() end)
        {:error, {:already_started, _pid}} -> :ok
      end

      {:ok, _cover_compiled} = :cover.compile_beam(Module1)

      ir_plt = build_missing_ir!(PLT.start(), [Module1])

      assert {:ok, %IR.ModuleDefinition{module: %IR.AtomType{value: Module1}}} =
               PLT.get(ir_plt, Module1)
    end
  end
end
