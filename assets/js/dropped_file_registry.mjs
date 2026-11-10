"use strict";

// The files and folders dropped on the page, by the path their %Hologram.File{} carries: a File for
// a file, a FileSystemDirectoryEntry for a folder. Both stay usable after the drop event, so the
// path keeps naming them. Entries are never freed, so a dropped file lives as long as the page, and
// a path kept in state doesn't survive a reload.
//
// TODO: read the entries by path through Elixir's File functions (#1532).
// TODO: free the entries a page no longer needs, along with the other client registries (#1211).
export default class DroppedFileRegistry {
  // Made public to make tests easier
  static entries = new Map();

  static put(path, value) {
    $.entries.set(path, value);
  }
}

const $ = DroppedFileRegistry;
