defmodule Hologram.Compiler.QueryExtractorCoverTest do
  # async: false - cover-compiling a module changes how every concurrent test
  # resolves its beam, so the covered window must not overlap other tests.
  use Hologram.Test.BasicCase, async: false

  import Hologram.Compiler.QueryExtractor

  alias Hologram.Commons.PLT
  alias Hologram.Query
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module143
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module144
  alias Hologram.Test.Fixtures.Entity.Module33, as: Entity33
  alias Hologram.Test.Fixtures.Entity.Module36, as: Entity36

  describe "derived_definition/3" do
    test "follows a cover-compiled query builder" do
      # Stop the cover server only when this test started it - an externally
      # started server (mix test --cover) owns its lifecycle and data.
      case :cover.start() do
        {:ok, _pid} -> on_exit(fn -> :cover.stop() end)
        {:error, {:already_started, _pid}} -> :ok
      end

      {:ok, _cover_compiled} = :cover.compile_beam(Module143)

      # A fresh PLT, so that the builder's IR is built from its beam while it is cover-compiled.
      {definition, read_modules} = derived_definition(Module144, :recent, PLT.start())

      assert definition ==
               {:query,
                %Query{
                  entity: Entity33,
                  sort: [position: :asc, id: :asc],
                  source: {Entity36, [:channel, :messages]},
                  take: 2
                }}

      assert read_modules == [Module143]
    end
  end
end
