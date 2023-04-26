defmodule Hologram.Template.SyntaxError do
  @moduledoc """
  Raised when the template markup is invalid.
  """

  defexception [:message]
end
