defmodule Hologram.Template.EventModifiers do
  @moduledoc false

  alias Hologram.TemplateSyntaxError

  # Event attribute base names that carry keyboard key filters.
  @keyboard_events ["$key_down", "$key_up"]

  # Modifier keys are matched against the event's boolean flags (event.ctrlKey,
  # event.altKey, etc.) rather than against event.key.
  @modifier_keys ~w(alt ctrl meta shift)

  # Named multi-character keys, snake-cased from the browser's event.key
  # (`ArrowDown` -> `"arrow_down"`). These readable names are what the developer writes - they
  # drive validation and did-you-mean. The string the matcher compares against, though, is the
  # normalized form: underscores stripped so it equals `event.key.toLowerCase()`
  # (`"arrow_down"` -> `"arrowdown"`), so matching is a plain equality against event.key.
  @named_keys ~w(
                  arrow_down arrow_left arrow_right arrow_up
                  backspace caps_lock delete end enter escape
                  home insert page_down page_up space tab
                ) ++ for(n <- 1..12, do: "f#{n}")

  @doc """
  Returns true if the given event attribute base name carries keyboard key filters.
  """
  @spec keyboard_event?(String.t()) :: boolean
  def keyboard_event?(base_name), do: base_name in @keyboard_events

  @doc """
  Parses the raw modifier segments of a keyboard event attribute into tagged key filters.

  Each segment becomes a `{:key, values}` tuple holding the resolved modifier flags and the
  single matched key. Raises `Hologram.TemplateSyntaxError` for an empty segment, an unknown
  multi-character key, or more than one key in a single filter.
  """
  @spec parse(list(String.t())) :: list({:key, list(String.t())})
  def parse(segments), do: Enum.map(segments, &parse_segment/1)

  defp did_you_mean(name) do
    candidates = @modifier_keys ++ @named_keys
    best = Enum.max_by(candidates, &String.jaro_distance(name, &1))

    if String.jaro_distance(name, best) >= 0.75 do
      ~s'Did you mean "#{best}"?'
    else
      ""
    end
  end

  defp parse_segment(segment) do
    values =
      segment
      |> String.split("+")
      |> Enum.map(&parse_token/1)

    if Enum.count(values, &(&1 not in @modifier_keys)) > 1 do
      raise TemplateSyntaxError,
        message: ~s'keyboard key filter "#{segment}" specifies more than one key'
    end

    {:key, values}
  end

  defp parse_token("") do
    raise TemplateSyntaxError, message: "keyboard key filter must not be empty"
  end

  defp parse_token(token) do
    name = String.downcase(token)

    cond do
      name in @modifier_keys ->
        name

      # `space` is the one alias: its event.key is a literal " ", which cannot be a token.
      name == "space" ->
        " "

      # Store the canonical event.key form: snake-case separators stripped at compile so the
      # client matcher is a plain equality. Stripping is named-key only - a single "_" is the
      # literal underscore key (event.key === "_"), handled by the single-char clause below.
      name in @named_keys ->
        String.replace(name, "_", "")

      String.length(name) == 1 ->
        name

      true ->
        raise TemplateSyntaxError,
          message: ~s(unknown keyboard key "#{token}". #{did_you_mean(name)})
    end
  end
end
