defmodule Hologram.TemplateSyntaxError do
  @moduledoc """
  Raised when the template markup is invalid.
  """

  defexception [:message]
end
