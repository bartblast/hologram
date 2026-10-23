defmodule Hologram.SQLError do
  @moduledoc """
  What `Hologram.DB.sql/3` returns under `{:error, ...}` and `Hologram.DB.sql!/3` raises when a
  statement fails.

  The code field is PostgreSQL's condition name for the failure as an atom
  (`:read_only_sql_transaction`, `:undefined_table`, `:syntax_error`), or nil when the failure did
  not come from the server, such as a timeout. The message is the server's text, or Hologram's for
  a statement refused because it writes.
  """

  @type t :: %__MODULE__{code: atom | nil, message: String.t()}

  defexception [:code, :message]
end
