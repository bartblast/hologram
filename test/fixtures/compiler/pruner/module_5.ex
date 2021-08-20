defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module5 do
  use Hologram.Page

  def template do
    ~H"""
      <Hologram.Test.Fixtures.Compiler.Pruner.Module6>
        <Hologram.Test.Fixtures.Compiler.Pruner.Module4 />
      </Hologram.Test.Fixtures.Compiler.Pruner.Module6>
    """
  end
end
