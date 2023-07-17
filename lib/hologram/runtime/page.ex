defmodule Hologram.Page do
  defmacro __using__(_opts) do
    quote do
      import Hologram.Component, only: [sigil_H: 2]
      import Hologram.Page

      @doc """
      Returns true to indicate that the callee module is a page module (has "use Hologram.Page" directive).

      ## Examples

          iex> __is_hologram_page__()
          true
      """
      @spec __is_hologram_page__() :: boolean
      def __is_hologram_page__, do: true
    end
  end

  @doc """
  Defines __hologram_layout__/0 which returns the page's layout module.

  ## Examples

      iex> __hologram_layout__()
      MyLayout
  """
  @spec layout(module) :: Macro.t()
  defmacro layout(module) do
    quote do
      def __hologram_layout__ do
        unquote(module)
      end
    end
  end

  @doc """
  Defines __hologram_route__/0 which returns the page's route.

  ## Examples

      iex> __hologram_route__()
      "/my_path"
  """
  @spec route(String.t()) :: Macro.t()
  defmacro route(path) do
    quote do
      def __hologram_route__ do
        unquote(path)
      end
    end
  end
end
