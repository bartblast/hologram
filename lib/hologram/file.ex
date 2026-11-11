defmodule Hologram.File do
  @moduledoc """
  A file or folder the browser holds, named by its path, like one dropped on a page.

  The path is under `/$hologram/drops/<id>/` and ends with the original name. It names the file only
  in the browser tab it was dropped in, for as long as the page stays open.
  """

  # TODO: reading the file with Elixir's File functions comes with the client-side file system
  # (#1532), and sending it to the server in a command with file uploads (#228), which the
  # deserializer refuses until then.

  @enforce_keys [:path]
  defstruct [:path]

  @type t :: %__MODULE__{path: String.t()}
end
