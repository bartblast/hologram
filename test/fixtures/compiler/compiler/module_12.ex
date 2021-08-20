defmodule Hologram.Test.Fixtures.Compiler.Module12 do
  use Hologram.Component

  def template do
    ~H"""
    <Hologram.Test.Fixtures.Compiler.Module13>
      <Hologram.Test.Fixtures.Compiler.Module11 />
    </Hologram.Test.Fixtures.Compiler.Module13>
    """
  end
end
