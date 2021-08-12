// based on: https://ghinda.net/article/script-tags/
// DEFER: already refactored; test
export default class ScriptsReloader {
  // https://html.spec.whatwg.org/multipage/scripting.html
  static EXECUTABLE_TYPES = [
    'application/javascript',
    'application/ecmascript',
    'application/x-ecmascript',
    'application/x-javascript',
    'text/ecmascript',
    'text/javascript',
    'text/javascript1.0',
    'text/javascript1.1',
    'text/javascript1.2',
    'text/javascript1.3',
    'text/javascript1.4',
    'text/javascript1.5',
    'text/jscript',
    'text/livescript',
    'text/x-ecmascript',
    'text/x-javascript'
  ]

  static dispatchDOMContentLoadedEvent(document) {
    const DOMContentLoadedEvent = document.createEvent('Event')
    DOMContentLoadedEvent.initEvent('DOMContentLoaded', true, true)
    document.dispatchEvent(DOMContentLoadedEvent)
  }

  static insertScript(document, script, callback) {
    const reloadedScript = document.createElement('script')
    reloadedScript.type = 'text/javascript'

    if (script.src) {
      reloadedScript.onload = callback
      reloadedScript.onerror = callback
      reloadedScript.src = script.src
    } else {
      reloadedScript.textContent = script.innerText
    }
  
    // DEFER: re-insert in the original location instead of head
    document.head.appendChild(reloadedScript)
    script.parentNode.removeChild(script)
  
    if (ScriptsReloader.isInlineScript(script)) {
      callback()
    }
  }

  static isExecutableScript(script) {
    const type = script.getAttribute('type')
    return !type || ScriptsReloader.EXECUTABLE_TYPES.includes(type)
  }

  static isInlineScript(script) {
    return !script.src
  }

  static reload(document) {
    let taskQueue = []

    Array.from(document.querySelectorAll('script'))
      .filter(script => ScriptsReloader.isExecutableScript(script))
      .forEach(script => {
        taskQueue.push(callback => {
          ScriptsReloader.insertScript(document, script, callback)
        })
      })

    const callback = () => { ScriptsReloader.dispatchDOMContentLoadedEvent(document) }
    ScriptsReloader.runSequentially(taskQueue, callback, 0)
  }

  static runSequentially(taskQueue, callback, index) {
    taskQueue[index](() => {
      ++index

      if (index == taskQueue.length) {
        callback()

      } else {
        ScriptsReloader.runSequentially(taskQueue, callback, index)
      }
    })
  }
}