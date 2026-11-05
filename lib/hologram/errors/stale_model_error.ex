defmodule Hologram.StaleModelError do
  @moduledoc """
  Raised when code other than the compile reads the data model while it is under a hold: the code
  loaded in the VM may be ahead of the model the last compile validated (see
  `Hologram.Entity.Model.hold/0`).
  """

  defexception message:
                 "the code changed since the last compile that validated the data model - " <>
                   "fix the compile error, if there is one, and save again"
end
