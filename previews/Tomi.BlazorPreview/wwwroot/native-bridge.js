// Native transport and DOM geometry only. Game state, event order and timing are C#.
window.tomiNative = (() => {
  let receiver = null;
  return {
    connect(ref) { receiver = ref; this.send({ command: 'ready' }); },
    send(message) {
      if (!window.TomiHost) throw new Error('Native host unavailable');
      window.TomiHost.postMessage(JSON.stringify(message));
    },
    receive(payload) { if (receiver) return receiver.invokeMethodAsync('Receive', payload); },
    measureMove(seat, mine, cardId, draw) {
      const arena = document.querySelector('.live-uno');
      if (!arena) return null;
      const bounds = arena.getBoundingClientRect();
      const hand = document.querySelector('[data-live-card="'+CSS.escape(cardId||'')+'"]') || arena.querySelector('.live-hand');
      const player = arena.querySelector('[data-seat="'+seat+'"]') || arena.querySelector('.seat.north');
      const from = draw ? arena.querySelector('.deck-button') : (seat === mine ? hand : player);
      const to = draw ? (seat === mine ? arena.querySelector('.live-hand') : player) : arena.querySelector('.discard');
      if (!from || !to) return null;
      const a=from.getBoundingClientRect(), b=to.getBoundingClientRect();
      return {x:a.left+a.width/2-bounds.left,y:a.top+a.height/2-bounds.top,dx:b.left+b.width/2-a.left-a.width/2,dy:b.top+b.height/2-a.top-a.height/2};
    },
    resetScroll() { window.scrollTo({top:0,left:0,behavior:"auto"}); },
    disconnect() { receiver = null; }
  };
})();
