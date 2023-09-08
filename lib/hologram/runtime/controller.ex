defmodule Hologram.Runtime.Controller do
  @doc """
  Extracts param values from the given URL path corresponding to the route of the given page module.
  """
  @spec extract_params(String.t(), module) :: %{atom => any}
  def extract_params(url_path, page) do
    route_segments = String.split(page.__hologram_route__(), "/")
    url_path_segments = String.split(url_path, "/")

    route_segments
    |> Enum.zip(url_path_segments)
    |> Enum.reduce([], fn
      {":" <> key, value}, acc ->
        [{String.to_existing_atom(key), value} | acc]

      _non_param_segment, acc ->
        acc
    end)
    |> Enum.into(%{})
  end
end
