defmodule Hologram.Test.Fixtures.Runtime.Layout.Module4 do
  use Hologram.Layout

  prop :a, :string
  prop :b, :integer, opt_1: 111, opt_2: 222

  def template do
    ~H""
  end
end
