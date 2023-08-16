defmodule Hologram.Compiler.Reflection do
  @doc """
  Determines whether the given term is an alias.

  ## Examples

      iex> alias?(Calendar.ISO)
      true

      iex> alias?(:abc)
      false
  """
  @spec alias?(any) :: boolean
  def alias?(term)

  def alias?(term) when is_atom(term) do
    term
    |> to_string()
    |> String.starts_with?("Elixir.")
  end

  def alias?(_term), do: false

  @doc """
  Returns true if the given term is a component module (a module that has a "use Hologram.Component" directive)
  Otherwise false is returned.

  ## Examples

      iex> component?(MyComponent)
      true
  """
  @spec component?(term) :: boolean
  def component?(term) do
    alias?(term) && {:__is_hologram_component__, 0} in term.__info__(:functions)
  end

  @doc """
  Returns true if the given term is a layout module (a module that has a "use Hologram.Layout" directive)
  Otherwise false is returned.

  ## Examples

      iex> layout?(MyLayout)
      true
  """
  @spec layout?(term) :: boolean
  def layout?(term) do
    alias?(term) && {:__is_hologram_layout__, 0} in term.__info__(:functions)
  end

  @doc """
  Lists Elixir modules belonging to any of the OTP apps used by the project (except :hex).
  Kernel.SpecialForms and Erlang modules are filtered out.
  """
  @spec list_elixir_modules() :: list(module)
  def list_elixir_modules do
    list_loaded_otp_apps()
    |> Kernel.--([:hex])
    |> list_elixir_modules()
  end

  @doc """
  Lists Elixir modules belonging to the given OTP apps.
  Kernel.SpecialForms and Erlang modules are filtered out.
  """
  @spec list_elixir_modules(list(atom)) :: list(module)
  def list_elixir_modules(apps) do
    apps
    |> Enum.reduce([], fn app, acc ->
      app
      |> Application.spec()
      |> Keyword.fetch!(:modules)
      |> Kernel.++(acc)
    end)
    |> Enum.filter(&alias?/1)
    |> Kernel.--([Kernel.SpecialForms])
  end

  @doc """
  Lists Elixir modules which are Hologram pages and that belong to any of the OTP apps in the project.
  """
  @spec list_pages() :: list(module)
  def list_pages do
    list_elixir_modules()
    |> Enum.filter(&page?/1)
  end

  @doc """
  Lists standard library Elixir modules, e.g. DateTime, Kernel, Calendar.ISO, etc.
  Kernel.SpecialForms module is not included in the result.
  """
  @spec list_std_lib_elixir_modules() :: list(module)
  def list_std_lib_elixir_modules do
    list_elixir_modules([:elixir])
  end

  @doc """
  Lists loaded OTP applications.

  ## Examples

    iex> list_loaded_otp_apps()
    [
      :inets,
      :logger,
      :stdlib,
      :file_system,
      ...
    ]
  """
  @spec list_loaded_otp_apps() :: list(:atom)
  def list_loaded_otp_apps do
    apps_info = Application.loaded_applications()
    Enum.map(apps_info, fn {app, _description, _version} -> app end)
  end

  @doc """
  Returns true if the given term is an existing module alias, or false otherwise.

  ## Examples

      iex> module?(Hologram.Compiler.Reflection)
      true

      iex> module?(Aaa.Bbb)
      false

      iex> module?(:abc)
      false
  """
  @spec module?(term) :: boolean
  def module?(term) do
    if alias?(term) do
      case Code.ensure_loaded(term) do
        {:module, _} ->
          true

        _fallback ->
          false
      end
    else
      false
    end
  end

  @doc """
  Returns BEAM definitions for the given module.
  If the BEAM file doesn't have debug info an empty list is returned.

  ## Examples

      iex> module_beam_defs(Hologram.Compiler.Reflection)
      [
        ...,
        {{:alias?, 1}, :def, [line: 14],
        [
          {[line: 16], [{:term, [version: 0, line: 16], nil}],
            [
              {{:., [line: 16], [:erlang, :is_atom]}, [line: 16],
              [{:term, [version: 0, line: 16], nil}]}
            ],
            {{:., [line: 19], [String, :starts_with?]}, [line: 19],
            [
              {{:., [line: 18], [String.Chars, :to_string]}, [line: 18],
                [{:term, [version: 0, line: 17], nil}]},
              "Elixir."
            ]}},
          {[line: 22], [{:_, [line: 22], nil}], [], false}
        ]}
      ]

      iex> module_beam_defs(Elixir.Hex)
      []
  """
  @spec module_beam_defs(module) :: list(tuple)
  def module_beam_defs(module) do
    debug_info =
      module
      |> :code.which()
      |> BeamFile.debug_info()

    case debug_info do
      {:ok, %{definitions: definitions}} ->
        definitions

      {:error, :no_debug_info} ->
        []
    end
  end

  @doc """
  Returns true if the given term is a page module (a module that has a "use Hologram.Page" directive)
  Otherwise false is returned.

  ## Examples

      iex> page?(MyPage)
      true
  """
  @spec page?(term) :: boolean
  def page?(term) do
    alias?(term) && {:__is_hologram_page__, 0} in term.__info__(:functions)
  end

  @doc """
  Returns the absolute path of the project.

  ## Examples

      iex> root_path()
      "/Users/bartblast/Projects/my_project"
  """
  @spec root_path() :: String.t()
  def root_path do
    File.cwd!()
  end

  @doc """
  Returns the absolute path of the project priv subdir for Hologram.

  ## Examples

      iex> root_priv_path()
      "/Users/bartblast/Projects/my_project/priv/hologram"
  """
  @spec root_priv_path() :: String.t()
  def root_priv_path do
    root_path() <> "/priv/hologram"
  end

  @doc """
  Returns the absolute path of the tmp directory.

  ## Examples

      iex> tmp_path()
      "/Users/bartblast/Projects/my_project/tmp"
  """
  @spec tmp_path() :: String.t()
  def tmp_path do
    root_path() <> "/tmp"
  end
end
