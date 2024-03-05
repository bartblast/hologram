defmodule Hologram.CompileError do
  @moduledoc """
  Raised when a page or a component can't be compiled.
  """

  defexception [:message]
end
