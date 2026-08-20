# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Benchmarks.Fixtures.Components.PlainPropComponent do
  @moduledoc false

  use Hologram.Component

  prop :title, :string

  def template do
    ~HOLO"""
    <div>{@title}</div>
    """
  end
end
