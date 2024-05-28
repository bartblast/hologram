defmodule Hologram.TemplateSyntaxError do
  @moduledoc """
  Raised when template markup is invalid.
  """

  defexception [:message]
end
