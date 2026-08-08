defmodule Hologram.Compiler.QueryExtractorCoverTest do
  # async: false - cover-compiling a module changes how every concurrent test
  # resolves its beam, so the covered window must not overlap other tests.
  use Hologram.Test.BasicCase, async: false
  use Hologram.Query

  import Hologram.Compiler.QueryExtractor

  alias Hologram.Query
  alias Hologram.Query.Param
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module18
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module19
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  describe "extract_module_queries/1" do
    test "extracts through a cover-compiled helper module" do
      case :cover.start() do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end

      on_exit(fn -> :cover.stop() end)

      {:ok, _cover_compiled} = :cover.compile_beam(Module19)

      nil_clause_term =
        Entity2
        |> filter(a: true)
        |> Query.normalize()

      bound_clause_term =
        Entity2
        |> filter(b: {:>=, %Param{name: :min_b}})
        |> Query.normalize()

      assert extract_module_queries(Module18) == [nil_clause_term, bound_clause_term]
    end
  end
end
