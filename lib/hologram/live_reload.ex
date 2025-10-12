defmodule Hologram.LiveReload do
  @asset_extensions [
    # Stylesheets
    ".css",
    # JavaScript
    ".cjs",
    ".js",
    ".mjs",
    # Images - Raster
    ".avif",
    ".bmp",
    ".gif",
    ".ico",
    ".jpeg",
    ".jpg",
    ".png",
    ".tif",
    ".tiff",
    ".webp",
    # Images - Vector
    ".svg",
    # Fonts
    ".eot",
    ".otf",
    ".ttf",
    ".woff",
    ".woff2",
    # Documents/Data
    ".json",
    ".pdf",
    ".xml",
    # Audio
    ".m4a",
    ".mp3",
    ".ogg",
    ".wav",
    # Video
    ".mp4",
    ".ogv",
    ".webm"
  ]

  @doc """
  Returns the list of file extensions to watch for assets.

  Covers common web asset formats.
  """
  @spec assets_extensions :: [String.t()]
  def assets_extensions, do: @asset_extensions
end
