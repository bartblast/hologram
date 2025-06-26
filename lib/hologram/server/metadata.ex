defmodule Hologram.Server.Metadata do
  alias Hologram.Server.Cookie

  defstruct cookie_ops: %{}

  @type t :: %__MODULE__{
          cookie_ops: %{
            String.t() => {:put, non_neg_integer, Cookie.t()} | {:delete, non_neg_integer}
          }
        }
end
