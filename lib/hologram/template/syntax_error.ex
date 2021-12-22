defmodule Hologram.Template.SyntaxError do
  defexception [:context, :message, :rest, :status, :token]
end
