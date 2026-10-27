"use strict";

import Type from "../type.mjs";

export default class FocusEvent {
  // The DOM focus and blur events are not cancelable, so preventDefault would be a no-op.
  static isDefaultAllowed = true;

  // Set while the runtime moves focus itself, to apply $focused or autofocus (see
  // Renderer.settleFocus). The DOM fires focus and blur for a programmatic .focus() exactly as for
  // a user's, but $focus and $blur report every focus change except the runtime's own: the state
  // already says where focus is, the way setting a controlled input's value fires no $change.
  // Reporting it back would also undo it - a $blur handler that clears the state would fire for
  // the field the state just moved focus away from.
  //
  // The flag covers everything that runs synchronously inside the move. Should an app's own focus
  // listener (not a Hologram binding) move focus again from inside it, those events read as the
  // runtime's too.
  static isRuntimeFocusChange = false;

  // TODO: add fields specific to FocusEvent
  static buildOperationParam(_event) {
    return Type.map();
  }

  static isEventIgnored(_event) {
    return FocusEvent.isRuntimeFocusChange;
  }
}
