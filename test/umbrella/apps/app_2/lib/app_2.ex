defmodule App2 do
  @moduledoc false

  @doc """
  Returns a value computed in the app_2 umbrella child app.
  """
  @spec message() :: String.t()
  def message do
    "Hello from app_2!"
  end
end
