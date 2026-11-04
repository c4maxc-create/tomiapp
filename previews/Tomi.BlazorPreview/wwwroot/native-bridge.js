// Message transport for the app's local WebView. Game logic and rendering are C#.
window.tomiNative = (() => {
  let receiver = null;
  return {
    connect(ref) { receiver = ref; this.send({ command: 'ready' }); },
    send(message) {
      if (!window.TomiHost) throw new Error('Native host unavailable');
      window.TomiHost.postMessage(JSON.stringify(message));
    },
    receive(payload) { if (receiver) return receiver.invokeMethodAsync('Receive', payload); },
    disconnect() { receiver = null; }
  };
})();
