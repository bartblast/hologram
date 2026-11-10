defmodule Hologram.MisuseError do
  @moduledoc """
  Raised when Hologram is called with something it does not take, like a relationship given where
  only an attribute goes. The call is a bug in the app, and the message says what to do instead.
  """

  defexception [:message]
end
