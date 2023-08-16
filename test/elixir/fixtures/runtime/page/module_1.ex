defmodule Hologram.Test.Fixtures.Runtime.Page.Module1 do
  use Hologram.Page

  route "/my_path"

  layout Hologram.Test.Fixtures.Runtime.Page.Module4
end
