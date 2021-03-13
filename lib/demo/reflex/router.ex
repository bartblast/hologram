defmodule Reflex.Router do
  defmacro __using__(_) do
    quote do
      require Reflex.Router
      import Reflex.Router
    end
  end

  defmacro reflex(path, view) do
    quote do
      get unquote(path), ReflexController, :index, private: %{reflex_view: unquote(view)}
    end
  end
end
