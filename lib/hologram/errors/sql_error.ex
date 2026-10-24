defmodule Hologram.SQLError do
  @moduledoc """
  The failure of an SQL read run through `Hologram.DB`: returned under `{:error, ...}` by the
  non-raising variant and raised by the raising one.

  The code field is PostgreSQL's condition name for the failure as an atom
  (`:read_only_sql_transaction`, `:undefined_table`, `:syntax_error`), or nil when the failure did
  not come from the server, such as a lost connection. The message is the server's text, or
  Hologram's for a statement refused because it writes.
  """

  @type t :: %__MODULE__{code: atom | nil, message: String.t()}

  defexception [:code, :message]
end
